# Flow CRM development status

Updated 2026-11-04. Baseline commit `53437ce`.

## Product objective

Deliver a paid, multi-tenant WhatsApp support, AI automation and marketing SaaS.
Each business owns its WhatsApp connections, team, contacts, knowledge and campaigns.
Self-service onboarding, subscriptions, server-enforced usage limits, monitoring and
documented backup/recovery are required parts of the final product.

## Evidence and current baseline

This document describes the current Desktop/Projeler/WPapp checkout, not a deployed
database. No remote backend or Meta account has been verified. Earlier uncommitted
campaign changes from the OneDrive workspace are absent. `pubspec.lock` was already
modified when this work began; preserve it outside milestone commits.

| Area | Implemented in source | Remaining work |
|---|---|---|
| Auth/tenancy | Session-driven password auth, confirmation-aware signup, server-owned profiles, self-service business creation, in-app invites (server RPCs, expiry, no escalation), code-based password recovery, memberships, tenant picker, module permissions | Invite emails (needs email provider), creating additional businesses from the tenant switcher, hosted SMTP/template setup |
| Inbox | Account-scoped inbound messages, inbound media download/storage/display, outbound photos/documents, durable reply queue, receipts, atomic opened/handoff actions, retry-safe controller, assignment/resolution/cancellation UI and backend | Pagination, audio/video sending, historical account mapping, account labels, per-agent unread state and runtime verification |
| AI | Scoped context/Responses, scheduled claims, token reservations/settlement, guarded replies and automatic handoffs | Configuration/usage UI refinement, subscription limits, operator recovery, model-quality/runtime evaluation |
| Templates | Scoped encrypted-connection sync, submission and header media upload; validated send bindings and form | Multi-account picker UI, broader template families (OTP, Flow, catalog), live provider verification |
| Campaigns | Shared audience RPC, parameters, versioned drafts, durable queue/workers, Riverpod/history, receipt reconciliation | Usage enforcement, scheduling/product polish and deferred runtime/provider verification |
| Handoff | Atomic request, shared ownership controls, queue cancellation, support episode timing backend, paginated/filterable list | Metrics presentation and runtime verification |
| Dashboard | Real tenant metrics from `dashboard_metrics` (conversations, inbound, bot vs human replies, median first-response/resolution, handoffs, campaign delivery/read, daily chart; today/7/30 days, Istanbul time) | Per-agent team performance, CSV export |
| Billing | Absent | Provider integration, subscription lifecycle, entitlements, usage limits |
| Operations | Additive migrations, growing setup guide, optional campaign/webhook scheduler scripts | Deployment, monitoring/alerts, retention, backup/restore and remaining worker schedules |
| Tests | Executed locally 2026-11-04: 13/13 SQL fixtures, 48/48 Deno unit tests, 13/13 functions type-check, 35/35 Flutter tests; inbound webhook-to-handoff smoke test on the local edge runtime; CI workflow added | Outbound provider sends, live Meta/OpenAI calls, broader security/workflow suites |

## Confirmed defects and release risks

- Fixed in source, runtime unverified: over-escaped audience date regex and ignored custom filters.
- Fixed in source, runtime unverified: empty send components replaced by validated parameters.
- Campaign sender replaced in source with durable snapshots, fenced claims and partial outcomes.
- Inbox text sending now uses encrypted tenant connections and a durable queue, runtime unverified.
- Audited 2026-11-04: every Edge Function service-role query filters by tenant, and the
  nine user-callable security-definer RPCs check `auth.uid()` plus tenant permission.
- Fixed 2026-11-04: `submit-template` and `upload-template-media` used the global Meta token
  (every tenant would submit into one shared WABA); both now use the tenant's own connection.
- Webhook signature validation and database-owned routing implemented in source, runtime unverified.
- Old bot callback replaced with durable ingestion and a scheduled scoped AI worker, runtime unverified.
- Inbound materialization preserves pending/handoff status and deduplicates side effects, runtime unverified.
- UI permissions alone are insufficient: RLS and cross-tenant foreign keys need audit.
- Existing API credentials were exposed in earlier debugging; rotate before deployment.
- Dashboard, invite delivery and some controls are prototypes/placeholders.

## Milestones and acceptance evidence

1. **Baseline**: inspect source, record status, requirements, source references and plan.
2. **Audience contract**: validated PostgreSQL filters shared by count and dispatch;
   unsupported filters rejected, permission and null behavior documented.
3. **Template sending**: persisted bindings, body/header/media/button payload builder,
   per-contact resolution, validation, form UI and authored regression tests.
4. **Campaign execution**: transactional recipient snapshot/claims, deduplication,
   bounded batching, retries, partial outcomes, reconciliation and delivery events.
   Unknown network outcomes must not be blindly retried; no false exactly-once claim.
5. **Flutter architecture**: repository/controller ownership, tenant-change safety,
   consistent error/loading states, responsive forms and replacement counter test.
6. **Tenant/security foundation**: constrained relations, least privilege, signed
   webhook ingestion, encrypted per-business connections and token lifecycle.
7. **Support workflows**: assignment, handoff, media, contact/consent management,
   knowledge automation and operational analytics.
8. **Commercial workflows**: self-service onboarding, invites, billing lifecycle,
   plans, entitlements and atomic usage enforcement.
9. **Operations/handoff**: monitoring, scheduled workers, deploy/setup instructions,
   migrations, backup/restore procedures and explicit external setup checklist.
10. **Release verification**: test execution and external integration checks after
    implementation, by the user's requested schedule. Unverified work remains labeled.

## Working rules

- Commit completed milestones with explicit paths; never include secrets or unrelated edits.
- Write tests alongside features. The verification phase started 2026-11-04: run the
  suites (see CI) for every change; live provider checks still need the owner's test number.
- Review diffs and use formatting/static checks as appropriate; these are not evidence
  of passing runtime tests. Do not mark the full product verified before release checks.
- Do not send real WhatsApp messages, provision paid resources, or charge subscriptions
  as a development check. Provide backend setup instructions for the owner.
- Preserve existing data with additive migrations; no database reset as an upgrade path.
- A completed milestone is not a completed SaaS. Keep all requirements visible here.

## Milestone log

- 2026-10-30: Baseline inspection completed. No suites run; no backend modified.
  Next: canonical audience RPC with strict validation and caller-scoped permissions.
- 2026-10-30: Audience matching moved to PostgreSQL for both preview and send.
  Added strict legacy-filter validation, invoker permissions, deterministic ordering,
  custom-filter propagation, stale-response suppression and surfaced preview errors.
  Removed the contradictory implicit custom-date rule and unsupported country/order
  fields from the form. Added transactional SQL fixtures; execution deferred.
  The sender's 100-recipient cap and queue reliability remain milestone 4 work.
- 2026-10-30: Template binding milestone implemented in source: additive JSON
  storage; one server-owned input manifest/parser; approved-template validation;
  text/contact/fallback/media/URL-button parameter construction; parameter form;
  persisted draft/send values; stale manifest suppression and wrapped action buttons.
  Draft writes now go through the repository. Unsupported component families fail
  explicitly. The placeholder counter test was replaced by meaningful form cases;
  server payload/validation regressions were authored. All suites remain unrun.
  Added DESIGN.md and UX-CONTRACT.md documenting existing theme and target behavior.
  Static Dart analysis and isolated TypeScript builder checking passed. Deno Edge
  entrypoint/runtime checks, live Meta conformance and visual checks are pending.
  Next: durable campaign snapshot/claims, duplicate protection, bounded workers,
  partial/unknown outcomes and delivery reconciliation, then Riverpod ownership.
- 2026-10-30: Campaign execution sub-milestone 4a: authored durable dispatch schema
  and service-only enqueue/claim/start/finalize/progress functions. Snapshot matching
  is atomic; unique normalized recipient keys prevent per-campaign duplicates;
  leases are fenced; expired dispatches become unknown, not automatic re-sends;
  retries are bounded. Client writes to legacy jobs are revoked, and new campaign
  template references enforce tenant equality. Historical jobs remain preserved.
  Added queue regression fixtures and `docs/CAMPAIGN_EXECUTION.md`. SQL and PL/pgSQL
  grammar parsing succeeded with pglast 8.7; no migration or test suite was executed.
  This foundation is not wired to the still-synchronous sender yet. Next: tenant
  connection resolution, replacement enqueue endpoint, bounded scheduled worker,
  verified delivery events and progress UI. Do not deploy 4a as a complete upgrade.
- 2026-10-30: Tenant WhatsApp connection foundation added before wiring workers:
  tenant-readable immutable phone metadata, service-only AES-GCM encrypted tokens,
  admin-only connect/disconnect with Meta app/scope/expiry/account checks, audit
  events and a scoped resolver. Closed the existing users-permission escalation
  path for direct membership writes. Added connection fields to campaigns and WABA
  identity to templates; legacy senders are not yet migrated to them.
  New endpoints/helpers and authored security tests pass Deno static type checking;
  new migration/SQL cases pass grammar parsing. All suites and live APIs remain
  unrun. Backend setup/rotation assumptions are in `docs/WHATSAPP_CONNECTIONS.md`.
- 2026-10-31: Campaign execution sub-milestone 4b: replaced the synchronous sender
  with authenticated enqueue and a secret-authenticated bounded background worker.
  Frozen tenant/account identity is checked at enqueue and again before dispatch;
  blocked configuration consumes no send attempts. Uncertain provider outcomes are
  not replayed, acknowledgements retry without another send, and partial progress
  is server-owned. Added the optional cron/Vault setup script without activating it.
  Template synchronization now uses encrypted tenant connections and atomic,
  account/language-scoped page imports, preserving ambiguous legacy records. Campaign
  selection excludes unlinked templates. Added delivery and sync regression suites
  and extended queue fixtures; all remain unrun. Deno type checking, Dart analysis,
  SQL/PLpgSQL grammar parsing and diff whitespace checks passed. Next: Riverpod ownership, stable
  client campaign IDs, draft/history/progress UI and signed delivery reconciliation.
- 2026-10-31: Campaign client milestone: added versioned draft persistence with
  stable client-generated IDs, permission/account checks, optimistic conflicts and
  direct-write revocation. Enqueue requires the reviewed draft revision. Riverpod
  owns remote reads and save/enqueue state; uncertain retries retain one immutable
  request and do not create another campaign. Added account-specific template
  selection, draft reopening, paginated history/progress/failure views and honest
  tag/recency labels. Consolidated template row parsing and guarded malformed saved
  binding data. Authored controller, SQL and narrow-layout regression cases; no
  suites run. Targeted Dart analysis and Deno type checking passed without issues;
  migration/fixture SQL and PL/pgSQL grammar parsing and diff checks passed.
  Remaining: verified inbound/status webhooks, tenant-scoped inbox/bot/template
  creation, support flows, commercial onboarding/billing/usage and operational
  hardening. Unsaved tab-navigation recovery and template-preview freshness remain
  explicit UI follow-ups; the complete SaaS is not ready to deploy.
- 2026-10-31: Webhook sub-milestone 6a: replaced the unsigned bot callback with one
  HMAC-verified receiver shared by the canonical and legacy URLs. Added a private,
  deduplicated event ledger, database-owned account routing, a bounded receipt
  processor and optional scheduler. Receipts reconcile only the correct tenant,
  number, recipient and current attempt; read/delivered evidence survives delayed
  failures. Delivery failures now appear in campaign recipient review. Added
  signature/ingestion and database receipt fixtures; execution remains deferred.
  Inbound messages are durably stored but not yet materialized into conversations;
  the replacement bot worker and tenant-scoped inbox sends are next. This slice
  must not be deployed by itself as a working bot replacement. See `docs/WEBHOOKS.md`.
  Targeted Dart analysis and SQL/PLpgSQL grammar parsing passed. Deno static type
  checking covers receivers, both workers and authored security fixtures; no suites,
  migrations, live subscriptions or provider sends were executed.
- 2026-10-31: Webhook sub-milestone 6b adds atomic inbound materialization into
  tenant/business-number conversations. Provider IDs deduplicate messages and unread
  increments. Normalized contact reuse preserves CRM names, support messages leave
  marketing consent unchanged, and pending/handoff status suppresses new bot jobs.
  Added client guards for provider identity, customer timestamps and inbound content,
  tenant composite references, bounded processing and private bot input jobs. Legacy
  threads remain unassigned to a sending number until an explicit mapping workflow.
  Authored duplicate, routing, rollback, state and permission fixtures without running
  them. SQL/PLpgSQL grammar parsing and Deno static checking passed. Human outbound
  sending, atomic read/handoff operations and the bot consumer remain next integration
  dependencies. No backend migration, schedule or external send was executed.
- 2026-10-31: Inbox lifecycle sub-milestone adds authenticated opened/handoff RPCs
  with server-owned employee identity and timestamps. Handoff request, conversation
  status, bot-job cancellation and audit event commit together. Stable client IDs
  make retries idempotent, including late retries after resolution. Direct lifecycle
  writes are guarded and direct handoff writes are revoked. Preserved the existing
  inbox plus handoff permission requirement. Moved the sheet into a reusable widget,
  retained notes after uncertain results, added inline recovery, keyboard-aware
  scrolling and tenant-change guards. Shared the existing UUID implementation with
  campaign creation. Authored SQL and widget/repository regressions without running
  suites. Targeted Dart analysis, SQL/PLpgSQL grammar parsing and diff checks passed.
  Static UI contract audit reported zero findings. Runtime interaction,
  concurrency and upgrade verification remain deferred. Shared unread semantics are
  preserved, with per-agent read cursors still pending.
- 2026-11-01: Inbox outbound milestone replaces the global-credential synchronous
  sender with authenticated enqueue, a private fenced queue and a scheduled worker.
  The original customer service window bounds queued replies, with permission,
  account and window checks again before dispatch. Human replies take ownership and
  cancel pending bot jobs. Campaign and inbox workers share delivery classification
  and acknowledgement safety. Verified receipts reconcile inbox outcomes through
  realtime display fields. Flutter now retains stable request IDs/text on uncertain
  results, distinguishes acceptance from delivery, guards back navigation and
  invalidates chats after business/session changes. Direct message writes are revoked
  and direct conversation updates are limited to tags. Authored SQL/controller/UI
  fixtures remain unrun. Type checking and targeted Dart analysis passed, with SQL
  grammar parsing and static UI contract audit also passing. Backend setup and
  limitations are documented in `docs/INBOX_EXECUTION.md`. AI processing, historical
  mapping, attachments, operator recovery and commercial workflows remain pending.
- 2026-11-01: AI context/adapter foundation adds exact latest-input identity,
  automation revisions, private knowledge/settings versions and a service-only
  consistent-snapshot context RPC. Retrieval uses bounded tenant-scoped lexical
  snippets and conversation history. Added a strict Responses adapter with scoped
  source-ID validation, response bounds, usage parsing and explicit uncertain/refused
  outcomes. New bot configuration starts inactive, and opening settings performs no
  implicit save. Existing activation values are preserved. SQL, adapter and config
  regressions are authored with execution deferred. The scheduled consumer, usage
  ledger and outbound finalization are still required to activate automated replies.
  Deno type checking, targeted Dart analysis, SQL/PLpgSQL grammar parsing and diff
  checks passed. The static UI contract audit reported zero findings.
  The integration plan and limitations are in `docs/AI_WORKER.md`.
- 2026-11-02: AI worker integration adds fenced claims, conservative token admission,
  idempotent settlement, UTC monthly usage and service-managed cap overrides. Late
  usage remains recordable after human takeover. Known temporary rate limits retry
  with provider minimums/backoff, while unknown consumption retains a visible hold.
  Bot replies use the inbox queue with current-input/ownership/configuration checks.
  Automatic handoffs cover missing knowledge, unsupported media, budget/provider
  failures and failed bot delivery. Reactions preserve pending questions and identical
  settings saves preserve active context versions. Added the worker scheduler script
  and authored DB/orchestration regressions. All suites, migrations and external
  requests remain unexecuted. Configuration and remaining integration work are in
  `docs/AI_WORKER.md`. The full SaaS still needs support lifecycle, commercial
  onboarding/billing, analytics, management UI and operational verification.
  Deno type checking covers the bot/inbox/campaign workers and their authored
  orchestration/provider cases. SQL/PLpgSQL grammar parsing and diff checks passed.

- 2026-11-03: Support workflow backend adds employee assignment, optimistic revisions,
  stable action replay, scoped team lookup and cancel-before-dispatch actions.
  Human enqueue claims unassigned work and rejects closed/other-owned threads.
  Pending human sends block ownership changes, while pending bot work is cancelled.
  Separate support episodes preserve reopen history and attribute late provider
  acceptance to the original case. Historical opening times remain unknown.
  SQL/role/lifecycle and client-error regressions are authored without execution.
  Flutter action controls and end-to-end integration are the next milestone.
  See `docs/SUPPORT_WORKFLOWS.md`; this checkpoint is not deployment-ready alone.
  Deno type checking, targeted Dart analysis, SQL/PLpgSQL grammar parsing and diff checks passed. No suites, migrations or external sends were run.

- 2026-11-04: Support UI integration adds one shared conversation-action sheet for
  inbox and handoff, with server-owned revisions and immutable uncertain retries.
  Tenant/session changes invalidate old panels. The handoff queue now has bounded
  status-filtered pages and chat navigation. Eligible human messages expose explicit
  cancel confirmation and worker-start conflict recovery. Related data refreshes
  after confirmed actions, while errors retain localized recovery guidance.
  Added repository/controller/widget regression cases with execution deferred.
  Chat tag/handoff actions moved into the overflow menu to fit the management action.
  Browser layout, keyboard, deployed-RPC and concurrency checks remain outstanding.
  Targeted Dart analysis and diff checks passed. The strict UI contract audit reported zero findings. Test suites, live provider operations and backend migrations remain unexecuted.

- 2026-11-04: Authentication foundation now follows SDK session events, including
  sign-out and delayed sign-in, with stream error handling and stable identity on
  routine refresh. Signup without a session stays in confirmation state. Removed
  the client profile-write dependency from login and added a server-owned profile
  migration/backfill. Login preserves password whitespace, adds inline validation
  and bounded scrolling, and separates membership fetch failure from no membership.
  Added mocked auth/UI and database profile fixtures without running suites.
  Self-service business creation, invitations and recovery remain next requirements.
  Setup and deferred verification are documented in `docs/AUTH_ONBOARDING.md`.
  Targeted Dart analysis, SQL/PLpgSQL grammar parsing and diff checks passed. The strict UI contract audit reported zero findings. Test suites and live auth/backend operations remain unexecuted.

- 2026-11-04: Roadmap Phase 0 (verification) started with Claude Code; the approved plan to
  finish, monetize and publish is in `docs/ROADMAP.md`. First execution of everything:
  - Upgrade path: the old January local database (14 migrations, 3 tenants, 66 messages;
    backed up to the git-ignored `supabase/.backups/`) took all 15 newer migrations with its
    data intact. A from-scratch `supabase db reset` (30 migrations + seed) also succeeds.
  - Defect found and fixed: PostgreSQL rejects regex repetition counts above 255, so
    `apply_whatsapp_template_page` (`{1,512}`) and `finish_inbox_dispatch` (`{1,506}`)
    raised at runtime: template sync failed for every page and accepted inbox/bot sends
    could never be finalized. Fixed additively in `20261104100000_regex_repeat_limits.sql`.
  - SQL fixtures 13/13 pass (`scripts/run_sql_tests.sh`) on both the upgraded and the fresh DB.
  - Deno 2.4: all 13 functions and 8 test modules type-check; 48/48 unit tests pass. Fixed a
    `TextEncoder` typing mismatch in `credential_cipher.ts` and its test. The local edge
    runtime (Deno 2.1-compatible) runs the code; type-check needs Deno 2.2+.
  - Flutter: analyze clean apart from 5 `withOpacity` deprecation infos; 35/35 tests pass after
    fixing test harness bugs only (fake responses lacked `request`, auth refresh timers and an
    isolate-awaiting `dispose()` under the fake clock, a stale `nullslast` order expectation).
  - Smoke test on the local edge runtime with generated secrets: webhook verification (200,
    wrong token 403), signed ingest (200, bad signature 401), webhook-worker materialized one
    conversation/message/bot job, wrong worker secret 401, bot-worker without an AI key handed
    off (`ai_configuration_invalid`) and queued the customer notice. Outbound sending was not run.
  - Config: Supabase URL/key now come from `--dart-define`; added `supabase/functions/.env.example`;
    removed the unused `app_server_config.dart` and three unused mock repositories; added CI
    (`.github/workflows/ci.yml`) for Flutter, Deno and migrations + SQL fixtures.
  Remaining Phase 0: hosted staging project and worker schedules, Meta test-number run of the
  outbound path, credential rotation (owner), validating the six `NOT VALID` constraints.

- 2026-11-04: Roadmap Phase 1, per-tenant templates. `submit-template` and
  `upload-template-media` were rewritten on the shared endpoint/auth/connection helpers and
  no longer read `WHATSAPP_ACCESS_TOKEN`/`WHATSAPP_WABA_ID`/`WHATSAPP_APP_ID` (removed from
  `.env.example`). Submission validates name/language/category/components
  (`_shared/template_submission.ts`), posts to the resolved connection's WABA and records the
  result via `apply_whatsapp_template_page`; upload uses Meta's Resumable Upload API with the
  tenant token and `META_APP_ID`, accepting only `upload:<id>?sig=<sig>` session paths.
  The Flutter picker now offers only JPEG/PNG, MP4 and PDF with matching size limits.
  Verified: 53/53 Deno tests (5 new), 36/36 Flutter tests (1 new), and a local edge-runtime
  smoke run of auth (401), membership/permission (403), validation (400/415) and connection
  resolution. Live Meta submission/upload is runtime unverified (needs a test number).

- 2026-11-05: Roadmap Phase 1, self-service onboarding. New migration
  `20261105090000_tenant_onboarding.sql`: `create_business`, `create_tenant_invite`,
  `revoke_tenant_invite`, `my_tenant_invites`, `respond_tenant_invite`; direct client
  writes to `tenant_invites` revoked; invites gain expiry, a single pending row per address
  and audit events. Closed an escalation path where a non-admin user manager could invite
  an administrator. Flutter: new `lib/features/onboarding` (create-business card, pending
  invites), a reworked first-run screen, invite form/revoke via RPCs with share text, and
  a code-based password reset screen (`AuthController.requestPasswordReset` /
  `completePasswordReset`). Recovery email template added for local Supabase.
  Verified: 14/14 SQL fixtures (new `tenant_onboarding.sql`), 41/41 Flutter tests (5 new),
  and a live local Auth/PostgREST run of create, invite, accept and password reset.
  Remaining: invite emails, hosted email template/SMTP setup (owner), second business
  from the tenant switcher.

- 2026-11-05: Roadmap Phase 1, WhatsApp connection screen. New admin-only "WhatsApp"
  destination (`lib/features/connections`) over the existing `manage-whatsapp-connection`
  function: list numbers with active/default/needs-reconnect state and token-expiry
  warnings, connect and reconnect forms with local validation and in-app Meta setup steps,
  disconnect with confirmation, and Turkish messages for every server error code. The form
  is pinned to the business it was opened for. Verified: 47/47 Flutter tests (6 new), and
  a local run of the function's 401/403/400/409 paths plus RLS hiding connection rows from
  non-admins. A live connect against Meta is runtime unverified (needs the test number).
  Not built yet: changing the default number without reconnecting, Embedded Signup.

- 2026-11-05: Roadmap Phase 1, contacts and consent. Migration
  `20261105100000_contacts_consent.sql`: consent source/basis/actor and opt-out evidence on
  `consented_contacts`, direct client consent writes revoked, CRM tag sync into the
  audience, opt-outs excluded from audience matching and re-checked at dispatch, and RPCs
  `upsert_contact`, `list_contacts`, `set_marketing_consent`, `import_contacts`. New
  "Kişiler" screen with search, paging, editing, consent with basis, and CSV import
  (Turkish Excel formats, chunked, explicit consent confirmation). See
  `docs/CONTACTS_CONSENT.md`. Verified: 15/15 SQL fixtures (new `contacts_consent.sql`),
  54/54 Flutter tests (7 new), live PostgREST run of import, list, opt-out and audience.
  Next: keyword opt-out from inbound messages, xlsx import.

- 2026-11-05: Roadmap Phase 1, real dashboard. Migration `20261105110000_dashboard_metrics.sql`
  adds `dashboard_metrics(tenant, days, timezone)`: definer function behind an explicit
  dashboard-permission check returning aggregates only (no content or identities), local-day
  buckets, legacy episodes excluded from medians, plus supporting indexes. The mock repository,
  the invented "estimated satisfaction" figure, the chart placeholder and the no-op quick
  actions were removed; the screen now shows live metrics with a today/7/30-day selector and a
  daily chart. Verified: 16/16 SQL fixtures (new `dashboard_metrics.sql`), 58/58 Flutter tests
  (4 new), live PostgREST call. Next: per-agent performance.

- 2026-11-06: Roadmap Phase 1, inbound media. Migration `20261106090000_inbox_media.sql`
  (private `inbox-media` bucket with tenant-folder Storage RLS, `message_media` queue fed by a
  trigger on customer media messages, fenced claim/finish with backoff and exhaustion
  handling, realtime publication), new `media-worker` with `_shared/media_download.ts`
  (Meta-host allow-list, 25 MB cap, size check), scheduler script, and chat rendering of
  images and file tiles via signed links (`url_launcher` now a direct dependency). See
  `docs/INBOX_MEDIA.md`. Verified: 17/17 SQL fixtures (new `inbox_media.sql`), 57/57 Deno tests
  (4 new), 63/63 Flutter tests (5 new), and a live local run: signed webhook queued the image,
  worker failed it cleanly without credentials, wrong secret 401, owner's signed link
  downloaded the file, another tenant got not-found. Live Meta download runtime unverified.
  CI: the dashboard commit's database job failed at stack start on the runner while a fresh
  local rehearsal passed; start now retries once and failures are published as annotations.

- 2026-11-06: Roadmap Phase 1, sending media. Migration `20261106100000_outbound_media.sql`:
  outbound `message_media` rows, Storage RLS for uploads into the caller's own
  `{tenant}/{conversation}/outbound/` folder, and `enqueue_inbox_media_message`, which validates
  type/size/path/caption and reuses every `enqueue_inbox_message` rule. `send-message` accepts
  `media`; `inbox-worker` uploads to Meta before the fenced send (`_shared/inbox_payload.ts`,
  `WhatsAppApi.uploadMedia`). Chat: attach button (photo/document, caption, preview), stable-ID
  upload and uncertain-retry handling in the send controller. Verified: 18/18 SQL fixtures (new
  `outbound_media.sql`), 61/61 Deno tests on 2.9.8 (4 new), 66/66 Flutter tests (3 new), live
  local run: agent upload allowed only in outbound/, media reply queued, bad media 422, worker
  deferred on an unusable credential without a send attempt. Live Meta upload/send runtime
  unverified. CI: pinned Deno 2.9.8 after `v2.x` resolved to a stricter TypeScript.

- 2026-11-06: Roadmap Phase 1, store readiness. App ID `com.flowcrm.app` and name "Flow CRM" on
  Android, iOS, macOS, Linux, Windows and web (Dart package name stays `wpapp`). Android:
  release signing from git-ignored `android/key.properties`, INTERNET permission in the main
  manifest (release builds previously had no network access), https VIEW query for
  url_launcher. Account menu in the top bar (another business, privacy policy, sign out — the
  app had no sign-out — and account deletion). Migration `20261106110000_account_deletion.sql`
  (`account_deletion_plan`, `my_account_deletion_plan`, `delete_account_data`;
  `conversations.last_opened_by` now ON DELETE SET NULL, which previously made deleting such
  users fail) and `delete-account` Edge Function (typed email confirmation, sole-admin block,
  stored-file cleanup, Auth user deletion, retry-safe). Build-time `PRIVACY_POLICY_URL` /
  `SUPPORT_EMAIL`. Release guide `docs/RELEASE.md`. Verified: 19/19 SQL fixtures (new
  `account_deletion.sql`), 61/61 Deno, 70/70 Flutter (4 new), live local deletion run
  (401/422/409 paths, user, solo business and its files removed, team business kept, login
  refused).

- 2026-11-07: Roadmap Phase 2b, business data model. Migration
  `20261107090000_catalog_bookings_leads.sql`: `resource_types` (validated field schema),
  `resources` (attribute validation trigger, external_* columns for a future sheet sync),
  `bookings` with the `bookings_no_overlap` GiST exclusion constraint and expiring holds,
  `leads`; new `catalog` module; agent RPCs `create_booking`/`set_booking_status`; service-only
  bot RPCs for search, availability, holds, confirmation and leads, always using the
  conversation's phone. See `docs/CATALOG_BOOKINGS.md`. Verified: 20/20 SQL fixtures (new
  `catalog_bookings.sql`), 70/70 Flutter tests, and a live five-round race of two concurrent
  sessions that left exactly one booking. Next: catalog/bookings/leads screens, then bot tools.

- 2026-11-07: Roadmap Phase 2b, Katalog screens (`lib/features/catalog`): preset-based types,
  field-driven item editor, bookings with hold confirm/cancel and agent booking (night/day/hour
  conventions), leads with status, `catalog` module in navigation and permissions. Verified:
  78/78 Flutter tests (8 new), 20/20 SQL fixtures, and a live PostgREST run of the app's exact
  queries (type/item insert, create_booking, P0015 on overlap, bookings range filter with
  resource embed, leads embed).

- 2026-11-07: Roadmap Phase 2a, bot tool calling. `_shared/bot_tools.ts` (strict tool definitions
  from the business's catalog, Istanbul date conversion, idempotent request keys, structured tool
  errors), a bounded multi-round loop in `generateAiReply` (4 rounds, 100 s, usage summed incl.
  failures, store=false-safe echo), tool-aware prompt and `tool_answer` reason (migration
  `20261107100000_bot_tool_answers.sql`), and bot-worker wiring. See `docs/AI_WORKER.md`.
  Verified: 68/68 Deno tests (7 new), 21/21 SQL fixtures (new `bot_tool_answers.sql`), and the real
  tool runner against the local database. Live OpenAI tool use runtime unverified (needs a key).
  Next: industry packs (2c) and interactive confirm buttons (2e).

- 2026-11-07: Roadmap Phase 2c, industry packs (rental, auto dealer, appointments): migration
  `20261107110000_industry_packs.sql` (`industry_pack_definition`, `industry_packs`,
  `apply_industry_pack`) and a two-step setup sheet in the Katalog and Bot screens. Verified:
  22/22 SQL fixtures (new `industry_packs.sql`), 80/80 Flutter tests (2 new), live PostgREST run.
