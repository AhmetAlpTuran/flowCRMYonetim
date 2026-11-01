# AI reply implementation

## Current implementation

The tenant context reader and OpenAI Responses adapter are implemented in source.
The scheduled consumer, usage reservation/settlement and bot outbound finalization
remain under construction. This foundation alone does not resume automated replies.
No AI requests, migrations or test suites were executed during development.

`20261101090000_bot_context.sql` adds an exact latest-customer-message pointer and
an automation revision to each conversation. Incoming provider messages update the
pointer even when timestamps tie. Older delayed messages preserve the latest pointer.
Human messages, human handoff requests and status changes invalidate the previous
automation revision. Settings and knowledge edits advance a private tenant context
version. Client writes cannot change these server-owned fields.

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

## Remaining worker integration

1. Claim jobs with a consistent conversation-before-job lock order. Serialize one
   active generation per conversation and invalidate superseded inputs.
2. Reserve the conservative token estimate before generation, using a private
   tenant-period usage ledger keyed by job and lease. Settle measured usage even
   when a human takes over while generation runs. Keep uncertain usage accounted
   for, and bound retries of definitive provider throttling.
3. Recheck the input ID, automation revision, context version, active setting and
   service window before accepting a generated result. Repeat relevant checks at
   outbound dispatch. Human-owned conversations must suppress pending bot output.
4. Queue bot replies through the existing inbox delivery path. Create human handoff
   requests atomically for missing knowledge, requested humans and failed generation.
   Use application-owned handoff notices. Route unsupported customer media to human
   review through this same job flow.
5. Add the scheduled worker, secrets/setup instructions, operational status and
   usage reporting. Connect limits to the later subscription entitlement lifecycle.

## Upgrade and verification

Apply the context migration after `20261030104000_inbox_dispatch_queue.sql` as part
of the complete AI integration. New settings/knowledge bounds are initially
`NOT VALID` to preserve historical rows. Audit existing values and support correction
through the product before validating `bot_settings_bounds` and
`knowledge_content_bounds`. Tenant identities become immutable on these records.

`supabase/tests/bot_context.sql`, `_shared/ai_reply_test.ts` and
`test/bot_config_test.dart` are authored and unrun. They cover scoped retrieval,
latest-input identity, human revision changes, inactive defaults, source validation,
bounded history, refusals, incomplete responses and transport uncertainty.
The completed worker still needs concurrent takeover, usage and delivery integration
fixtures plus live model-quality/provider checks in the agreed verification phase.
