# Inbox outbound delivery

Implemented in source on 2026-11-01. Deployment, runtime tests and provider checks
remain deferred. The replacement AI consumer, attachments, account-management UI,
operator recovery and commercial usage enforcement remain separate milestones.

## Request and ownership

Flutter now uses `send-message` for the supported Supabase deployment. The former
alternate Node HTTP sender is removed from the chat path. Each send has a client UUID
created before the first request. Riverpod retains the UUID and original text while
the outcome is uncertain. The backend accepts `tenant_id`, `conversation_id`,
`message_id` and `body`, with a maximum of 4096 Unicode code points in the text.

The endpoint authenticates the session and calls `enqueue_inbox_message` as that user.
The database checks inbox permission, the conversation's tenant and its immutable
WhatsApp connection/customer identity. Employee identity and display name come from
the session and profile. A caller-supplied sender name has no authority.

One transaction inserts the visible message and private dispatch row, updates the
preview, takes human ownership and cancels outstanding bot jobs. An existing handoff
stays in handoff. Other statuses become pending, preserving human control on incoming
messages. The later support lifecycle must provide explicit resolution/resume actions.

Repeating an identical request ID returns its existing state, including after the
service window expires. Reusing it for another tenant, employee, conversation or body
fails. This does not enqueue a second message. Direct client writes to messages are
revoked. Conversations permit client tag updates, with other state written by RPCs
and workers. Worker leases and credentials remain private.

## Service window and queue

The database requires a verified customer message in the preceding 24 hours. It
checks this at enqueue and dispatch. Legacy conversations with no business-number
mapping require explicit account resolution. There is no default-number inference.

Each queued reply also retains the original customer's window expiry. A newer
incoming message cannot extend the lifetime of an old blocked reply. This bounds
stale queued content while permitting a newly composed reply in the new window.
The claim sweep expires old blocked work even when credential preparation fails.

`inbox-worker` authenticates a separate `INBOX_WORKER_SECRET`, claims up to ten jobs
and processes at most five concurrently within a start-work deadline. Private
sequence numbers preserve order among active replies in one conversation. Other
conversations can proceed independently. Unknown outcomes allow later explicitly
composed replies to proceed, while the unknown attempt remains available for review.

An unstarted expired lease returns to the queue with a new token. A sending lease
that expires becomes unknown and retains its token for a late acknowledgement.
Before marking a dispatch, the database rechecks the employee's permission, channel
identity, customer window, conversation closure and connection availability.
It locks conversation before dispatch. Credential problems defer work without
consuming a provider attempt.

The shared `whatsapp_delivery.ts` implementation owns response classification for
both campaigns and inbox replies. It makes one external call after a successful
dispatch marker. A lost database acknowledgement can retry persistence without
another provider call. Explicit throttling rejections back off, up to five provider
attempts. Transport failures, malformed responses and ambiguous server errors become
unknown. A disconnect or lifecycle change cannot recall a dispatch already started.

## Receipts and UI

Verified receipts reconcile by tenant, connection, recipient and provider ID. A
compound message UUID and lease UUID callback can recover an unknown attempt or a
receipt arriving before the API acknowledgement. Read/delivery evidence survives
older failure notifications. The existing receipt worker now reconciles both queues.

A transactional trigger copies public display state into `messages`, allowing the
existing realtime subscription to update the chat without exposing worker tokens.
The UI labels queueing, provider acceptance, delivery, read, failure and uncertainty
separately. Refresh remains available when realtime is delayed. Compose input stays
visible after errors and freezes during an uncertain request. Retrying checks that
same request. Back navigation asks before discarding a draft or leaving an uncertain
request. Session/business changes invalidate the old chat and require reopening it.

Browser reload recovery, explicit operator decisions for unknown sends, per-agent
unread cursors and paginated message history remain pending. Composer state lives in
memory, and a reload can lose an unsaved draft. The message record remains in the
database once enqueue committed. Attachments remain disabled in the current UI.

## Setup and deferred verification

Apply `20261030104000_inbox_dispatch_queue.sql` after the preceding migrations.
Deploy the matching Flutter client, `send-message`, `inbox-worker`, `webhook-worker`
and `campaign-worker` together with shared modules. Old synchronous clients require
an upgrade because request IDs and queued-result semantics are now required.

Configure the encrypted tenant connections, `WHATSAPP_API_VERSION`, and a new random
32–256 character `INBOX_WORKER_SECRET`. Store the same worker secret in Vault as
`inbox_worker_secret`, alongside `project_url`. Manually apply
`supabase/ops/schedule_inbox_worker.sql` during backend setup. No schedule has been
activated during development.

Authored suites include `supabase/tests/inbox_dispatch_queue.sql`,
`test/inbox_send_test.dart` and the extended shared delivery cases in
`supabase/functions/_shared/campaign_delivery_test.ts`. All remain unrun. Verify
concurrent claims, crash/timeout boundaries, rotated credentials, permission changes,
receipt ordering, service-window edges, Unicode limits, frontend navigation and
real provider callback conformance in the agreed verification phase.
