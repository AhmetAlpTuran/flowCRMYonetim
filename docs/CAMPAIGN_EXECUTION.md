# Campaign execution contract

Database foundation is implemented in `20261030092000_campaign_dispatch_queue.sql`,
with connection fencing and blocked-state handling in `20261030094000_campaign_worker_integration.sql`.
`send-campaign` now enqueues only; `campaign-worker` owns external sends. Client
controller/history integration and verified delivery receipts remain unfinished.
Deploy these as part of the complete, verified upgrade, not as independent patches.

## Snapshot and idempotency

`enqueue_campaign` is service-only. The Edge endpoint must authenticate the caller,
load the campaign/template using tenant-scoped queries, validate bindings with the
shared builder, then pass the authenticated user ID and exact reviewed configuration.
The RPC rechecks membership, locks the campaign, verifies that configuration has not
changed, and freezes all matching recipients in one transaction. No 100-row cap.

`campaign_recipient_audience` applies the existing `campaign_audience` filter and
deduplicates valid international phone numbers; preview count uses the same function.
Spaces, parentheses, periods, hyphens, a leading plus and international 00 prefix are
normalized. Country codes are never guessed. Unsupported characters or invalid
numbers become explicit failed recipients. The latest consent record wins duplicate
phone matches, with ID as a deterministic tie-breaker.

An enqueue retry for the same campaign returns its original recipient count.
One unique `(campaign_id, recipient_key)` record prevents duplicate recipients.
Queued configuration is immutable. Legacy `message_jobs` are retained, protected
from client writes, and prevent automatic replay of a previously attempted campaign.
The UI must retain a stable campaign ID across network retries; creating a new
campaign for the same button click is not covered by per-campaign idempotency.

## Worker protocol

1. Claim at most 25 recipients with `claim_campaign_dispatches` (default 10).
   Claims use `FOR UPDATE SKIP LOCKED`, random fencing tokens and 120-second leases.
   Expiry cleanup is bounded to 500 records per call.
2. Resolve the frozen template values with the shared parameter builder. Persist
   local validation failures with `fail_campaign_validation`; no provider attempt.
3. Resolve the tenant's WhatsApp connection and server-side credentials. This must
   precede `start_campaign_dispatch`; missing configuration must not become an
   irreversible send. The resolver reads only the frozen tenant/account, decrypts
   its credential and never falls back to global credentials. Preparation failures
   become `blocked` and are reconsidered after five minutes without spending an
   attempt. The database rechecks active connection identity at the send marker.
4. Call `start_campaign_dispatch` with the exact lease token. It rechecks consent
   record/phone presence and current template approval/definition, then records the
   irreversible dispatch marker and increments attempts. Send only if it returns true.
5. Send exactly once for that marker, with a bounded network timeout shorter than
   the lease. Classify the response and call `finish_campaign_dispatch`.
6. Retry a lost database acknowledgement without repeating the external send.
   Accepted acknowledgements with the same message ID are idempotent. Refresh
   campaign progress in a separate transaction.

| Outcome | Queue state | Automatic retry |
|---|---|---|
| Lease lost before dispatch marker | queued with new token | safe |
| Provider accepts and returns wamid | accepted | never |
| Definitive transient rejection | retry_wait | up to 5 total attempts |
| Invalid values / permanent rejection | failed | never |
| Missing/disabled/expired connection before marker | blocked | configuration recheck after 5 minutes |
| Timeout, connection loss or worker loss after marker | unknown | never |
| Consent record removed or phone changed before dispatch | cancelled | never |

Unknown means the message may have been sent. There is no exactly-once guarantee
across PostgreSQL and an external API without provider idempotency. Late definitive
responses may reconcile the same fencing token. Human review/webhook reconciliation
must precede any operator decision to send a replacement.

Retries back off from 30 seconds, doubling per attempt, capped at 1 hour; a longer
provider Retry-After up to 1 hour takes precedence. The worker retries only structured
4xx rejections with HTTP 429 or Meta codes 130429/131056. Other structured 4xx errors
are failures; malformed replies and 5xx responses are unknown. Error 190 flags the
connection for attention only if its metadata version has not changed since loading.
Raw provider messages are not stored or logged. Delivery failure after acceptance
is not automatically resent. Current provider code conformance remains a live check.

The worker claims 10 rows, processes at most 5 concurrently and stops starting more
work after 30 seconds. Database requests are bounded to 10 seconds and provider
requests to 15 seconds. At most two database acknowledgements follow one send.
Unstarted claims expire safely; post-marker losses become unknown. The scheduler
invokes the worker every 10 seconds using a dedicated high-entropy bearer secret.
See `supabase/ops/schedule_campaign_worker.sql` and `BACKEND_SETUP.md`.

## Progress and delivery

`campaign_progress` reads tenant-scoped authoritative counts. `accepted` means API
acceptance, not delivery. Pending, failed, unknown, cancelled, delivered, read and
delivery-failed counts are separate. Mixed success/failure ends as `partial`;
unknown/blocked outcomes require attention once other work finishes.
`refresh_campaign_progress` maintains the cached campaign status but the live summary
remains authoritative. An expiry sweep can leave the cached status stale when no
new jobs from that campaign are returned; clients must read `campaign_progress`.

Delivery columns are reserved for verified webhook events; event deduplication,
out-of-order receipt handling and reconciliation are not wired in this foundation.
Legacy summaries are labeled so zero new-queue rows are not presented as a new send
with zero recipients. An actually empty audience cannot be enqueued.

## Deferred verification

`supabase/tests/campaign_dispatch_queue.sql` authors checks for >100 recipients,
normalized duplicates, invalid numbers, repeated enqueue, configuration conflicts,
worker-only privileges, lease fencing/reclamation, unknown outcomes, late acceptance,
partial counters and legacy replay protection. It has not been executed.
It also covers account mismatch, disconnected connections and blocked attempts.
`campaign_delivery_test.ts` authors classification, redaction, transport loss,
lost acknowledgement and no-duplicate-call cases with injected fake dependencies.
No real provider sends or test suites have been run.

The verification phase also needs concurrent sessions: hold one claim transaction
open, claim from another session, and assert disjoint recipients; concurrently
enqueue one campaign and verify one snapshot. Exercise migration upgrades with old
jobs, consent removal, retry exhaustion, recipient deletion and worker crashes.
No live WhatsApp messages should be needed for these database checks.
