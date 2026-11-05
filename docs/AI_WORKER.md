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

## Catalog tools (roadmap Phase 2a, 2026-11-07)

When a business has catalog types (`resource_types`), the worker offers the model
strict function tools built by `_shared/bot_tools.ts` from that catalog:

| Tool | Database function | Notes |
|---|---|---|
| `search_catalog` | `bot_search_resources` | type, text, field filters (`equals` or `min`/`max`), price range; active items only |
| `check_availability` | `bot_check_availability` | bookable types only |
| `hold_booking` | `bot_create_booking_hold` | 15-minute hold bound to the conversation |
| `confirm_booking` / `cancel_booking` | `bot_set_booking_status` | only bookings of this conversation |
| `my_bookings` | `bookings` (service read) | this conversation's live holds/bookings |
| `create_lead` | `bot_create_lead` | test drive, trade-in, financing, callback, other |

- The model passes dates as `YYYY-MM-DD` (and `HH:MM` + hours for hourly services); the
  server converts them to Istanbul times (nightly stays 14:00 check-in, 11:00 check-out).
- The customer's phone always comes from the conversation; the model cannot supply one.
- Holds and leads use request keys derived from job + tool + arguments, so a retried
  job never doubles a side effect; a different job (a later customer message) creates a
  new hold, and the overlap constraint refuses conflicting ones (`not_available`).
- Tool errors return structured results (`not_available`, `hold_expired_or_cancelled`,
  `not_found`, `invalid_input`) for the model to explain instead of failing the reply.
- `generateAiReply` loops at most `MAX_TOOL_ROUNDS` (4) within a 100 s budget (the job
  lease is 120 s), sends tool calls back without stored item ids (`store: false`), keeps
  encrypted reasoning for reasoning models, and sums usage across rounds, including when
  a later round fails. Reservations for tool-enabled requests scale with the rounds.
- Replies based on tool results use reason `tool_answer`
  (`20261107100000_bot_tool_answers.sql`); a business with a catalog but no knowledge
  entries is no longer handed off automatically.
- The prompt requires an explicit customer confirmation in a later message before
  `confirm_booking`, forbids invented items or prices, and treats tool output as data.

Verified: Deno unit tests for definitions, date conversion, runner mapping, request
keys, error mapping and the loop (round trip, usage sums, round limit, failure billing);
SQL fixture `bot_tool_answers.sql`; and the real runner executed against the local
database (search, availability, hold, idempotent re-hold, overlap refusal, my_bookings,
confirm, lead with the conversation's phone). A live OpenAI tool conversation is runtime
unverified until an API key is configured.

## Booking confirm buttons (roadmap Phase 2e, 2026-11-07)

When a reply follows exactly one new hold in that job, the worker attaches WhatsApp
reply buttons "Onayla" (`booking:confirm:<id>`) and "İptal" (`booking:cancel:<id>`).

- `complete_bot_reply` (`20261107120000_bot_reply_buttons.sql`) accepts an optional
  `buttons` array: 1-3 items, titles 1-20 characters, ids only of the form
  `booking:(confirm|cancel):<uuid>` for a booking of the same tenant and conversation,
  and a reply text of at most 1024 characters. Anything else is refused (`22023`). The
  outbound message is stored as `message_type = 'interactive'` with the buttons in
  `provider_content.interactive.buttons`; replies without buttons stay plain text.
- `inbox-worker` sends such a message as an interactive `button` message
  (`_shared/inbox_payload.ts`) and falls back to text when the buttons or body are invalid.
- A customer's tap arrives as an `interactive` `button_reply`. The bot worker reads its id
  (`parseButtonTap`) and runs `confirm_booking`/`cancel_booking` directly, without calling
  the model: no tokens are spent, and the reply is fixed Turkish text (confirmed with item and
  dates, expired hold, cancelled, or a fallback that points to a representative).
  The booking must still belong to the conversation, so a forwarded or forged id fails.
- Typed confirmations ("evet") still go through the model and `confirm_booking`.

Verified: Deno tests (`booking_buttons_test.ts`: button building, tap parsing, reply
texts, hold tracking, interactive payload), SQL fixture `bot_reply_buttons.sql`
(foreign-conversation, over-long and arbitrary ids refused; valid buttons stored as
interactive; plain replies unchanged), and a live local run through the webhook,
webhook-worker and bot-worker: a tapped "Onayla" confirmed the hold, queued the fixed
confirmation reply and consumed no AI tokens. Delivery to a real phone is runtime
unverified until a Meta test number is connected.

## Hybrid knowledge search (roadmap Phase 2f)

After `bot_reply_context`, the worker replaces the context's knowledge with
`bot_knowledge_search`. This covers manual notes and uploaded document passages, with
full-text search (Turkish letters folded) fused with vector search over embeddings of
the customer's message. Embedding or search failures fall back to full text and then to
the context's own notes. See `docs/KNOWLEDGE_DOCUMENTS.md`.

## Multiple bots (roadmap Phase 2g, `20261108100000_multiple_bots.sql`)

`bot_settings` remains the business's main bot ("Ana bot"). `bot_profiles` holds up to ten
extra bots, each with its own name, tone, language, instructions, model and memory. They are
managed only through `save_bot_profile` (with a stable client ID) and `delete_bot_profile`,
using the bot permission. Each WhatsApp number has `bot_profile_id` (null means the main bot)
and `bot_enabled` (false means humans only), changed through `set_connection_bot`.

- `effective_bot_settings(tenant, connection)` returns the bot of a number, shaped like
  `bot_settings`. Enqueueing (`materialize_whatsapp_message`), `claim_bot_reply`,
  `prepare_bot_reply`, `bot_reply_context`, `complete_bot_reply` and
  `bot_dispatch_allowed` all use it. An extra bot works even when the main bot is off or
  missing.
- Changing a bot or a number's assignment bumps the bot context version, so an
  in-flight reply hands off instead of answering with stale settings.
- Replies and handoff notices carry the answering bot's name and language. The handoff
  notice is Turkish or English, depending on the bot's language.
- `bot_reply_jobs.bot_profile_id` records which bot finalized a job, for per-bot
  reporting. Null means the main bot. Deleting a bot moves its numbers back to the main
  bot and keeps job history.
- Knowledge and catalog tools are shared by all bots of a business; per-bot knowledge
  scopes are a possible follow-up. Industry packs configure the main bot.

App: the Bot screen lists the main bot and the extra bots, each opening the same editor
(the main bot cannot be deleted). It also shows a "Yanıt veren bot" picker for each number:
the main bot, an extra bot, or "Bot kapalı".

Verified:
- SQL fixture `multiple_bots.sql` covers:
  - permissions, the 10-bot limit, validation and tenant isolation
  - the revoked direct writes
  - routing and enqueueing through the real webhook path, and the context and job
    attribution
  - switching a number off, and delete fallback
- 5 Flutter widget tests.
- A live local run: a member managed bots and assignments through PostgREST, and a
  webhook message on an English extra bot's number was handled by that bot through the
  bot worker.

## Listing photos

`send_photos(resource_id)` (always offered with a catalog) attaches up to 3 of the item's
photos to the reply. `trackPhotos` removes the storage paths from the tool result before
the model sees it. The worker adds `photos: [{path, caption}]` to the decision, and
`complete_bot_reply` validates them and queues one image dispatch per photo after the text.
See `docs/CATALOG_BOOKINGS.md`.

## Industry pack evaluation (`scripts/bot_eval.ts`)

There are 12 scripted conversations across the three industry packs
(`_shared/bot_eval.ts`). They run the real prompt and tool loop against an in-memory catalog
(3 cars, 2 rooms, 1 service) and check:

- **Stock search:** the bot searches before recommending (budget and gear) and never
  invents stock (asked for a BMW, it says there is none).
- **Car dealer requests:** test drives become leads, photos are sent with `send_photos`,
  and the bot makes no discount promises.
- **Bookings:** a hold is placed with the 15-minute notice and never confirmed in the same
  turn, and it is confirmed after an explicit "Evet".
- **Unknown facts and refusals:** no invented deposit amounts, no medical advice, and a
  handoff when the customer asks for a person.

Run it with your OpenAI key. It costs a few cents, and nothing touches a database or WhatsApp:

```
docker run --rm -e OPENAI_API_KEY -e EVAL_MODEL=gpt-4o-mini -e EVAL_REPEAT=3 \
  -v "<repo>:/app" -w /app denoland/deno:2.9.8 \
  deno run --allow-env --allow-net=api.openai.com scripts/bot_eval.ts
```

A case passes only if every repeat passes. Use `EVAL_REPEAT=3` or more, because model output
varies. The checks are unit-tested with a scripted model (`bot_eval_test.ts`: a
well-behaved run passes; invented stock, skipped search and premature confirmation fail).
Results against a real model are runtime unverified until the owner runs it; add a case
whenever a pilot conversation goes wrong.
