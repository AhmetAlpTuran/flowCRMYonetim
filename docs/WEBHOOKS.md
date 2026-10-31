# Verified WhatsApp webhooks

Implemented in source, not deployed or runtime-verified. This is the receipt and
durable-ingestion slice. Incoming messages are queued but inbox materialization and
the replacement AI worker are still pending. Do not deploy this slice alone as a
finished replacement for the existing bot.

## Receiver boundary

`whatsapp-webhook` is the canonical callback. `bot-reply` now delegates to the same
receiver, preserving the old URL without its unsigned/default-tenant send path.
There is no caller-supplied tenant routing, global token fallback or direct AI/send
operation in either receiver.

GET subscription verification uses `WHATSAPP_WEBHOOK_TOKEN`, a separately generated
32–256 character secret, and returns the challenge as plain text. POST verifies
`X-Hub-Signature-256` with HMAC-SHA256 over the exact raw bytes using `META_APP_SECRET`.
JSON parsing and persistence happen only after signature verification. Platform JWT
verification is disabled for these two public Meta callbacks; this does not disable
application signature checks. Never log incoming bodies, signatures or secrets.

Requests are bounded to 2 MiB, a ten-second body-read deadline and 1,000 normalized
events. Supported message identity
currently uses international phone numbers and wamid IDs. Business-scoped user IDs,
coexistence sync events and non-message subscription fields need explicit follow-up.
All entries and changes are visited; status payloads retain only recipient, state,
attempt callback and numeric error code. Raw provider error text is omitted. Inbound
content remains private in the event ledger for subsequent message processing.

`ingest_whatsapp_events` is service-only and routes by the immutable WABA and phone
mapping in PostgreSQL. Unknown mappings stay unassigned in the private ledger; they
never fall back to a default tenant. No authenticated/anonymous role can read or
write this ledger. A hash of provider identity deduplicates each message/status
event. A 200 response is returned only after commit; a failed commit returns 503 so
Meta can retry. Replaying a signed request does not create another event.

## Campaign receipts

`webhook-worker` authenticates `WEBHOOK_WORKER_SECRET` before invoking the database
receipt processor. Each transaction processes up to 50 status events using
`FOR UPDATE SKIP LOCKED`. Failed application rolls back that event's changes and
records a sanitized code; other events can continue. Unmatched receipts retry every
five minutes for seven days, allowing registration/acknowledgement races to settle.
Repeated processing errors become an explicit error after 20 attempts. Error events
need operator review; automatic external sends are never part of reconciliation.

A receipt must match the tenant, connected sending number and recipient. A known
provider message ID updates only its dispatch. To recover a send whose response was
lost, the worker includes `dispatch UUID:lease UUID` in `biz_opaque_callback_data`.
Only the current sending/unknown attempt with that exact token may be reconciled.
Legacy callbacks containing only the dispatch ID cannot recover an unknown attempt.
Provider conformance for this callback field remains a live verification item.

Receipts can arrive before the API response. Reconciliation records acceptance and
the provider ID; a later matching acceptance acknowledgement remains idempotent.
Delivery/read evidence cannot be downgraded by delayed sent/failed events. Read
counts imply delivery even when no separate delivered event was received. A failed
delivery stays separate from API rejection and appears in the recipient failure
view. The authoritative progress RPC reflects receipts immediately; cached campaign
list status can lag until refreshed by campaign processing.

Inbox message receipts are retained as unmatched until the scoped outbound-message
integration exists. No unscoped updates to legacy message IDs are performed.

## Deployment and operations (deferred)

1. Apply `20261030101000_whatsapp_webhook_events.sql` after the earlier migrations.
2. Configure `META_APP_SECRET`, `WHATSAPP_WEBHOOK_TOKEN`, and a separate random
   `WEBHOOK_WORKER_SECRET` in Edge secrets. Keep all three out of Flutter/source.
3. Deploy both receiver URLs, `webhook-worker`, and the updated `campaign-worker`.
   Configure Meta's messages subscription using the canonical callback URL.
4. Store `webhook_worker_secret` and the existing `project_url` in Supabase Vault;
   manually apply `supabase/ops/schedule_webhook_worker.sql`. It replaces only its
   own named schedule. No scheduler has been activated by development work.
5. Monitor pending age, unmatched identities, signature failures and processing
   errors. Alert on growing queues; do not log message content to diagnose failures.
6. Event retention/purge, tenant deletion, inbox/bot consumption, billing-related
   receipt metadata and operator replay controls remain operations/integration work.
   The current seven-day unmatched retry window is not a data-retention policy.

`whatsapp_webhook_test.ts` and `supabase/tests/whatsapp_webhook_events.sql` are authored
but unrun. They cover signatures, verification, storage failure, all-entry parsing,
deduplication, tenant boundaries, early receipts, unknown recovery and receipt order.
Concurrent transaction tests, receiver load/latency, live subscriptions and provider
payload conformance are required in the agreed verification phase.
