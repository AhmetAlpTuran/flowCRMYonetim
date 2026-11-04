# WhatsApp media in the inbox

Updated 2026-11-06. Implemented and verified on the local stack; real downloads from and
uploads to Meta are runtime unverified until a test number is connected.

## Flow

1. `whatsapp-webhook` stores the signed event; `webhook-worker` materializes the message.
2. The `messages_queue_inbound_media` trigger queues customer `image`, `video`, `audio`,
   `document` and `sticker` messages in `message_media` (media ID, MIME type, file name,
   caption). Outbound and malformed media are ignored.
3. `media-worker` (scheduled, `supabase/ops/schedule_media_worker.sql`, secret
   `MEDIA_WORKER_SECRET`) claims up to 3 jobs per run with fenced leases, resolves the
   media ID with the tenant's own token, downloads it (token sent only to
   `*.fbsbx.com`/`*.whatsapp.net` over HTTPS, no redirects, 25 MB cap, size checked) and
   stores it in the private `inbox-media` bucket at `{tenant}/{conversation}/{message}.{ext}`.
4. Transient errors retry with exponential backoff (30 s doubling, 5 attempts); provider
   4xx, disconnected/expired numbers and invalid IDs fail immediately; files over 25 MB
   are marked `too_large` and stay in WhatsApp. A lease that expires on the final attempt
   is failed (`attempts_exhausted`) instead of staying stuck.

## Access

- `message_media` rows are readable by members with the inbox permission; clients cannot
  write them.
- Storage RLS lets only inbox members of the tenant in the path's first folder read the
  object; the app requests one-hour signed links. Another tenant gets "not found" and
  there is no public URL.
- `message_media` is in the realtime publication, so an open chat refreshes when a
  download finishes.

## App

Chat bubbles show images inline (tap to open full size) and voice notes, videos and
documents as a tile with name and size that opens in the device's player or viewer via
`url_launcher`. Pending, failed and too-large media show an explanation; captions replace
the `[image]`-style placeholders.

## Deployment

Deploy `media-worker`, set `MEDIA_WORKER_SECRET`, store it in Vault as
`media_worker_secret`, then run `supabase/ops/schedule_media_worker.sql`.

## Sending media (`20261106100000_outbound_media.sql`)

1. The agent picks a photo (JPG/PNG, 5 MB) or document (PDF, Word, Excel, TXT, 16 MB) and
   adds an optional caption (1024 characters).
2. The app uploads it to `inbox-media/{tenant}/{conversation}/outbound/{message}.{ext}`.
   Storage RLS allows inserts only into the caller's own tenant/conversation outbound
   folder with an allowed extension; there is no overwrite or delete from clients. The
   path uses the message's stable request ID, so a retry reuses the same object (a
   duplicate upload is treated as already done).
3. `send-message` with `media` calls `enqueue_inbox_media_message`, which checks type,
   size (from the stored object), path and caption, then runs the normal
   `enqueue_inbox_message` (permission, ownership, closed/assigned rules, 24-hour
   window, connection health, idempotency) and records an outbound `message_media` row.
4. `inbox-worker` uploads the file to Meta (`/{phone_number_id}/media`) inside
   `prepare`, before the fenced send starts, so an upload failure defers the job
   without using a send attempt; then it sends `image`/`document` with the media ID and
   caption.
5. The chat shows sent files with the same media view as received ones. An uncertain
   send keeps the file locked for retry with the same ID; a definitive failure can be
   retried or removed.

## Not yet

In-app audio playback, sending audio/video, retention/cleanup policy for stored media
(roadmap Phase 4, KVKK).
