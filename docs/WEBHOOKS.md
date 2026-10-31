# Verified WhatsApp webhooks

Implemented in source, pending deployment and runtime verification. Verified inbound
messages now materialize into account-scoped conversations and create durable bot
input jobs. The replacement AI worker and scoped human outbound path remain pending.
Deploy the completed inbound/outbound/bot integration together during verification.

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

## Incoming conversations

The worker also calls `process_whatsapp_messages` in a separate bounded transaction.
Each event materializes its contact, conversation, message, unread increment and
optional bot input job atomically. A per-event failure rolls back those effects and
records `message_processing_failed`. Processing retries after five minutes, with a
20-attempt limit. Unknown account mappings retry for seven days. Disconnected accounts
produce ignored events. Connections needing attention can still receive messages.

Conversation identity is `(connection_id, customer_phone)`. The same customer can
have separate conversations with each business number. Within a tenant, normalized
phone matching reuses the earliest existing CRM contact and preserves its name.
Concurrent inbound contact creation uses a tenant/customer transaction lock. Existing
duplicate contacts and manual contact creation need the later contact-management
deduplication workflow. Legacy conversations keep their original unscoped identity.

Both ledger identity and `(connection_id, wa_message_id)` protect against replay.
Older delayed messages remain visible and increment unread counts while preserving
the newer preview. Customer service timestamps are capped at the server's original
receipt time. Client roles cannot forge those timestamps or rewrite verified customer
input. Media and structured input retain their provider content with a text/caption
preview or `[type]` marker. Downloading and rendering media remain separate work.

An active bot setting creates one private `bot_reply_jobs` row for a current text,
button or interactive input in an open conversation. Missing settings disable job
creation. Pending and handoff status preserve human ownership. A newer message can
reopen a closed conversation. Receiving a support message leaves campaign consent
unchanged. Bot execution still needs conversation serialization, stale-input checks,
handoff fencing, usage accounting and a scoped outbound queue.

Read/handoff actions now use atomic RPCs. Handoff also cancels queued, leased and ready
bot jobs, clearing their lease tokens. The future bot worker must lock conversation
before job and recheck ownership and token before creating an outbound response.
The legacy human sender remains integration work so all messages use the correct
connection and the preview timestamp includes human replies.
Account labels in the inbox, per-agent unread state and historical channel mapping
also remain pending. The protections added here cover incoming provider identity and
content. The broader legacy client-write surface still requires its planned audit.

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

1. Apply `20261030101000_whatsapp_webhook_events.sql` and then
   `20261030102000_whatsapp_inbound_conversations.sql` and
   `20261030103000_inbox_lifecycle_actions.sql` after the earlier migrations.
   Audit and validate historical tenant foreign keys using the backend setup guide.
2. Configure `META_APP_SECRET`, `WHATSAPP_WEBHOOK_TOKEN`, and a separate random
   `WEBHOOK_WORKER_SECRET` in Edge secrets. Keep all three out of Flutter/source.
3. Deploy both receiver URLs, `webhook-worker`, and the updated `campaign-worker`.
   Configure Meta's messages subscription using the canonical callback URL.
4. Store `webhook_worker_secret` and the existing `project_url` in Supabase Vault;
   manually apply `supabase/ops/schedule_webhook_worker.sql`. It replaces only its
   own named schedule. No scheduler has been activated by development work.
5. Monitor pending age, unmatched identities, signature failures and processing
   errors. Alert on growing queues; do not log message content to diagnose failures.
6. Event retention/purge, tenant deletion, bot execution, billing-related
   receipt metadata and operator replay controls remain operations/integration work.
   The current seven-day unmatched retry window is not a data-retention policy.

`whatsapp_webhook_test.ts` and `supabase/tests/whatsapp_webhook_events.sql` are authored
but unrun. They cover signatures, verification, storage failure, all-entry parsing,
deduplication, tenant boundaries, early receipts, unknown recovery and receipt order.
Concurrent transaction tests, receiver load/latency, live subscriptions and provider
payload conformance are required in the agreed verification phase.

`supabase/tests/whatsapp_inbound_conversations.sql` is also authored and unrun. It
covers separate business numbers/tenants, formatted contact reuse, duplicate side
effects, handoff and pending preservation, inactive bots, delayed inputs, future
timestamps, rollback after a bot-job failure, client-write guards and tenant RLS.
SQL/PLpgSQL grammar parsing and worker type checking passed. Runtime constraints,
privileges, deadlocks and concurrent worker behavior still need verification.
