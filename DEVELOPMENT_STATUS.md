# Flow CRM development status

Updated 2026-11-01. Baseline commit `53437ce`.

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
| Auth/tenancy | Password auth, memberships, tenant picker, module permissions | Auth events, onboarding, tenant boundary audit, invitations and recovery |
| Inbox | Account-scoped inbound messages, durable text reply queue, receipts, atomic opened/handoff actions, retry-safe controller | AI integration, assignment/resolution, pagination, attachments, historical account mapping, account labels and per-agent unread state |
| AI | Settings, knowledge CRUD, private input jobs with handoff preservation | Replacement AI worker, knowledge retrieval, human ownership fencing, usage accounting |
| Templates | Scoped encrypted-connection sync, legacy submission/upload, validated send bindings and form | Scoped submission/upload and multi-account UI, broader template families, provider verification |
| Campaigns | Shared audience RPC, parameters, versioned drafts, durable queue/workers, Riverpod/history, receipt reconciliation | Usage enforcement, scheduling/product polish and deferred runtime/provider verification |
| Handoff | Atomic authorized request, idempotent retry, bot-job cancellation, list | Assignment, processing/closure, outbound bot fencing, response/resolution metrics |
| Dashboard | Mock statistics/chart | Real tenant metrics and team performance |
| Billing | Absent | Provider integration, subscription lifecycle, entitlements, usage limits |
| Operations | Additive migrations, growing setup guide, optional campaign/webhook scheduler scripts | Deployment, monitoring/alerts, retention, backup/restore and remaining worker schedules |
| Tests | Campaign, connection, webhook/inbound, controller, payload and UI regressions authored | Broader security/workflow suites and execution deferred by user |

## Confirmed defects and release risks

- Fixed in source, runtime unverified: over-escaped audience date regex and ignored custom filters.
- Fixed in source, runtime unverified: empty send components replaced by validated parameters.
- Campaign sender replaced in source with durable snapshots, fenced claims and partial outcomes.
- Inbox text sending now uses encrypted tenant connections and a durable queue, runtime unverified.
- Some service-role queries retrieve related objects by ID without tenant equality.
- Webhook signature validation and database-owned routing implemented in source, runtime unverified.
- Old bot callback replaced with durable ingestion. Replacement bot execution remains pending.
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
- Write tests alongside features, but do not run suites until the user requests that phase.
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
