# Campaign execution contract

Database foundation implemented in `20261030092000_campaign_dispatch_queue.sql`.
The Edge worker and client progress integration are the next slice. Do not deploy
this migration alone as a completed queue upgrade; the legacy sender remains active
until the replacement endpoint/worker is committed and deployed together.

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
   irreversible send. Per-tenant connection integration remains required.
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
| Timeout, connection loss or worker loss after marker | unknown | never |
| Consent record removed or phone changed before dispatch | cancelled | never |

Unknown means the message may have been sent. There is no exactly-once guarantee
across PostgreSQL and an external API without provider idempotency. Late definitive
responses may reconcile the same fencing token. Human review/webhook reconciliation
must precede any operator decision to send a replacement.

Retries back off from 30 seconds, doubling per attempt, capped at 1 hour; a longer
provider Retry-After up to 1 hour takes precedence. The worker must whitelist
definitive transient rejections; it must not classify every network/5xx failure as
safe to retry. Delivery failure after acceptance is not automatically resent.

## Progress and delivery

`campaign_progress` reads tenant-scoped authoritative counts. `accepted` means API
acceptance, not delivery. Pending, failed, unknown, cancelled, delivered, read and
delivery-failed counts are separate. Mixed success/failure ends as `partial`;
unknown outcomes require attention. `refresh_campaign_progress` maintains the cached
campaign status but the live summary remains authoritative.

Delivery columns are reserved for verified webhook events; event deduplication,
out-of-order receipt handling and reconciliation are not wired in this foundation.
Legacy summaries are labeled so zero new-queue rows are not presented as a new send
with zero recipients. An actually empty audience cannot be enqueued.

## Deferred verification

`supabase/tests/campaign_dispatch_queue.sql` authors checks for >100 recipients,
normalized duplicates, invalid numbers, repeated enqueue, configuration conflicts,
worker-only privileges, lease fencing/reclamation, unknown outcomes, late acceptance,
partial counters and legacy replay protection. It has not been executed.

The verification phase also needs concurrent sessions: hold one claim transaction
open, claim from another session, and assert disjoint recipients; concurrently
enqueue one campaign and verify one snapshot. Exercise migration upgrades with old
jobs, consent removal, retry exhaustion, recipient deletion and worker crashes.
No live WhatsApp messages should be needed for these database checks.
