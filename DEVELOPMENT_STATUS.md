# Flow CRM development status

Updated: 2026-10-30. Baseline commit: `53437ce`.

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
| Inbox | Conversations, text replies, tags, realtime, read events | Assignment, pagination, attachments, per-agent unread state, resilient sends |
| AI | Settings, knowledge CRUD, webhook reply | Signed webhooks, phone-to-tenant routing, deduplication, human ownership, usage accounting |
| Templates | Submit, sync, media upload | Validated send parameters, tenant-specific credentials, supported-type validation |
| Campaigns | Draft/create, synchronous send, consented contacts | Canonical filters, parameters, durable queue, claims, retries, progress and delivery |
| Handoff | Request creation/list | Assignment, processing/closure, bot pause, response/resolution metrics |
| Dashboard | Mock statistics/chart | Real tenant metrics and team performance |
| Billing | Absent | Provider integration, subscription lifecycle, entitlements, usage limits |
| Operations | Migrations, local config | Deployment guide, observability, backup/restore and scheduled workers |
| Tests | Generated counter test references missing MyApp | Replace and author meaningful suites; execution deferred by user |

## Confirmed defects and release risks

- Flutter audience date regex is over-escaped; count and send use different logic.
- Custom campaign filters are stored but ignored by the sender.
- Send components always become an empty list; dynamic parameters cannot work.
- Sender stops at 100 contacts, has no durable claim, and marks failures completed.
- Jobs are recorded after external delivery: retries can duplicate dispatch.
- Some service-role queries retrieve related objects by ID without tenant equality.
- Webhook POST lacks signature validation and accepts caller-selected/default tenant.
- Bot resets conversation status to open and does not honor human ownership.
- bot-reply uses Dart-style string `.isEmpty` in TypeScript.
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
