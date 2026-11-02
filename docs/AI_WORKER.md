# AI reply implementation

## Current implementation

The context reader, Responses adapter, scheduled consumer, usage ledger and guarded
outbound integration are implemented in source. Deployment and runtime verification
remain deferred. No AI requests, migrations or test suites were executed during
development.

`20261101090000_bot_context.sql` adds an exact latest-customer-message pointer and
an automation revision to each conversation. Incoming provider messages update the
pointer even when timestamps tie. Older delayed messages preserve the latest pointer.
Emoji reactions remain visible but leave the latest actionable input intact.
Human messages, human handoff requests and status changes invalidate the previous
automation revision. Settings and knowledge edits advance a private tenant context
version. Saving identical values with a new timestamp preserves that version.
Client writes cannot change these server-owned fields.

`bot_reply_context` is service-only and requires a current leased job, an open
conversation, the exact latest customer input and active bot settings. Its stable
database function reads one consistent query snapshot. It derives tenant, account
and conversation scope from the job and related records. Context includes bounded
history from that conversation and knowledge from that tenant.

Retrieval ranks lexical matches and supplies up to five relevant snippets, including
matches beyond the start of an article. With no lexical match, it supplies up to five
recent entries. The model must choose handoff when this material is insufficient.
Semantic retrieval quality and factual answer quality need representative evaluations.
The current knowledge implementation supplies retrieved context for generation.

`ai_reply.ts` prepares a strict JSON response schema with reply/handoff decisions,
bounded text and source IDs. It preserves the selected existing model, with a
server-provided model allowlist. The current UI uses `gpt-4o-mini`. Request data
excludes tenant, customer and conversation routing identifiers. The model receives
business preferences, scoped knowledge and conversation text as data, with no tools.
Recipient selection and database mutations belong to the application.

The adapter bounds serialized context to 96,000 UTF-8 bytes, reducing older history
and then lower-ranked sources. It limits output to 1600 tokens and validates the
result at 4096 Unicode code points. Factual replies must reference IDs supplied in
that request. Source-ID membership alone cannot establish factual correctness.
Refusals, incomplete output, invalid schema/IDs and transport uncertainty remain
explicit typed outcomes. They retain measured usage when available.

Calls use the fixed HTTPS Responses endpoint, a deadline, bounded response reading,
disabled redirects, `store: false` and no automatic transport retries. The storage
setting controls Responses application state. Provider abuse-monitoring retention
requires its own deployment/privacy review under OpenAI's data controls.

New bot configurations default to inactive. Fetching missing settings returns an
inactive draft without a database write. Existing saved activation values are
preserved. Enabling a new business's bot requires an explicit save.

## Claims, completion and human ownership

`bot-worker` authenticates its dedicated secret, performs bounded maintenance and
processes up to three independently claimed jobs concurrently. Each claim locks one
conversation before its job. A current lease excludes another claim for that
conversation. Superseded queued inputs are cancelled. An unstarted expired lease
can retry, with a maximum of three job attempts. An expired started generation
becomes uncertain and hands the current conversation to a person.

Preparation binds the exact input and context revisions before any model call.
Completion checks them again. Context-version share locks establish the preparation,
completion and dispatch boundaries relative to settings/knowledge edits. A human
takeover or newer input suppresses old output. A changed configuration routes the
current input to human review. Generation already in progress can still consume
tokens after a takeover, so settlement is independent of the job's terminal state.

One transaction finalizes the job, creates its message/dispatch or human handoff,
and records the audit event. Repeated acknowledgements preserve that result. Bot
messages use the same encrypted-account inbox transport as human messages, with
source-specific ownership checks immediately before dispatch. Already-started
external requests cannot be recalled by a later lifecycle change.

Missing knowledge, unsupported media, model failures, budget exhaustion and explicit
human requests create a handoff task. Application-owned notices use Turkish for the
recognized Turkish language settings and English otherwise. Expired service windows
create the task without an out-of-window notice. Handed-off conversations remain
under human control when later customer messages arrive.

`reconcile_bot_delivery_failures` routes a failed or uncertain queued bot answer to
the human queue when it still belongs to the current input. It also handles settings
changes after generation but before dispatch. It preserves existing human ownership
and ignores superseded answers. A late positive receipt can update delivery evidence
without undoing a human handoff already created.

## Usage admission and retries

Usage periods are UTC calendar months. `AI_MONTHLY_TOKEN_LIMIT` is the deployment's
default per-tenant cap. A service-managed `tenant_ai_limits` row overrides that cap.
Tenant administrators can read aggregate usage and limits but cannot increase them.
Subscription-driven provisioning of those overrides remains billing integration work.

Preparation atomically compares consumed plus reserved tokens against the cap and
reserves a conservative request estimate. It stores one reservation per job/lease.
Temporary pressure from active reservations can wait through the bounded retry path.
Exhausted capacity routes to a person. Admission is based on token units, with pricing
and invoice integration handled separately in the later billing milestone.

Provider-reported usage replaces its reservation exactly once. Definitive rejected
requests settle at zero. Unknown consumption retains its budget hold and remains
separate from measured consumption. Abandoned reservations become explicitly unknown
after five minutes when their lease is no longer active. They remain eligible for
late measured settlement. Operator recovery and provider-usage reconciliation UI
remain pending. Held estimates must not be presented as measured billable usage.

Only identified temporary OpenAI rate limits automatically retry. Billing/spend/quota
errors hand off immediately. Retry scheduling honors the provider minimum and adds
exponential backoff with jitter. Delays over one hour or beyond the reply window
hand off. Transport uncertainty and ambiguous server failures also hand off, with
their usage held for review. Persistence acknowledgements retry independently from
generation, preventing repeated model calls after a lost DB response.

The shared retry-hint parser also fixes WhatsApp retries. Provider minimums over the
supported delay now produce an explicit reviewable failure. The sender preserves the
provider's requested minimum instead of clipping it to an earlier retry time.

## Configuration and operations

Apply `20261101091000_bot_worker.sql` after the context migration. Deploy `bot-worker`,
the updated `inbox-worker` dependencies and the shared modules together. The new
`inbox_dispatches.source` and source-specific start checks are required for bot sends.

Configure server-side `OPENAI_API_KEY`, `BOT_WORKER_SECRET` and
`AI_MONTHLY_TOKEN_LIMIT`. The worker secret must be a separate random 32–256 character
value. Optional `OPENAI_ALLOWED_MODELS` is a comma-separated server allowlist with
`gpt-4o-mini` as its default. Choose the default token cap for the intended service
plan. Zero blocks generations for tenants without a positive override. Missing or
invalid local configuration routes inputs to humans without a model call.

Store `bot_worker_secret` and `project_url` in Supabase Vault, then manually apply
`supabase/ops/schedule_bot_worker.sql` during backend setup. It invokes every ten
seconds and replaces only its own named schedule. Development has not activated it.

Monitor queue age, unknown reservations, handoff reasons and the worker response's
`configuration_ready`, `delivery_reconciliation` and `outcomes` fields. Local readiness
only confirms configuration presence/shape. Provider authentication is evaluated by
actual requests. A successful scheduler HTTP response alone cannot establish healthy
generation or delivery. Live alerts and operator-facing recovery remain operations
milestone work.

## Upgrade and verification

Apply the context migration after `20261030104000_inbox_dispatch_queue.sql` as part
of the complete AI integration. New settings/knowledge bounds are initially
`NOT VALID` to preserve historical rows. Audit existing values and support correction
through the product before validating `bot_settings_bounds` and
`knowledge_content_bounds`. Tenant identities become immutable on these records.

`supabase/tests/bot_context.sql`, `supabase/tests/bot_worker.sql`, the shared
`ai_reply_test.ts` and `bot_execution_test.ts`, and `test/bot_config_test.dart` are
authored and unrun. They cover scoped retrieval,
latest-input identity, human revision changes, inactive defaults, source validation,
bounded history, refusals, incomplete responses and transport uncertainty.
Additional authored cases cover reservation contention, settlement after takeover,
lost acknowledgements, expiry, provider retry hints, stale queued answers, media
handoffs and client privilege boundaries. Multi-session concurrency, model quality,
provider conformance and full UI workflows still need the agreed verification phase.
Assignment/resolution UI, usage/billing integration, historical account mapping and
operator recovery remain product implementation work.
