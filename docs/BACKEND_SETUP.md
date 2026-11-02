# Backend setup and upgrade notes (in progress)

The SaaS backend is not ready for production deployment. This guide grows with each
milestone. No migrations have been applied automatically by this implementation work.

## Support workflow integration checkpoint

`20261102090000_support_workflows.sql` follows the bot worker migration. It adds
assignment, optimistic/idempotent lifecycle actions, queued-human-message
cancellation and separate support episodes. The matching Flutter action controls
are still being implemented. Deploy the complete integration together because
closed conversations now require an explicit reopen before human sending.
The updated `send-message` endpoint maps closed/assigned conflicts for the client.
No additional external secrets or scheduler are required by this migration.
See [SUPPORT_WORKFLOWS.md](SUPPORT_WORKFLOWS.md) for permissions, timing semantics,
legacy data handling and deferred concurrency/upgrade verification.

## Audience filtering milestone

Apply ordered migrations, including `20261030090000_campaign_audience.sql`, before
shipping the updated Flutter client or send-campaign function. Use a fresh isolated
development database first; back up an existing database before upgrades. Do not
reset an existing database to apply this migration.

The new RPCs are `campaign_audience(p_tenant_id, p_filter)` and
`count_campaign_audience(p_tenant_id, p_filter)`. They share the same matcher and
retain RLS via invoker rights. Anonymous execute is revoked. Authenticated callers
need the campaigns permission for the tenant; service-role callers are server only.

The filter format preserves existing stored campaigns:

```json
{
  "segment": "VIP",
  "last_contacted": "7d",
  "custom": [{"field": "Etiket", "operator": "icerir", "value": "VIP"}]
}
```

All rules are ANDed. Segment/tag comparison is exact and case sensitive. Last-contact
days are elapsed 24-hour periods relative to database transaction time. The custom
`Son iletisim` field uses `>` for older than N days, `<` for within N days, and `=`
for the elapsed-day bucket. Values accept `7` or legacy `7 gun`. Unknown last-contact
timestamps do not match date rules. Unsupported keys/fields/operators fail explicitly.
Country and purchase-count predicates require future schema/integration work.

Preview is live: contacts may change before dispatch. The queue now freezes the
recipients at enqueue time using the same matcher; the old 100-recipient sender cap
has been removed. Queue deployment and deferred verification are still required.

## Template send-values milestone

Apply `20261030091000_campaign_template_bindings.sql` after the audience migration.
Deploy both `campaign-template-inputs` and `send-campaign` with the shared module
present before releasing the new client. Keep authenticated invocation enabled.
The manifest endpoint authenticates the user, checks the tenant's campaigns
permission, and scopes its service query by both tenant ID and template ID.
It needs the existing `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SERVICE_ROLE_KEY`.
These credentials are server configuration, never Flutter configuration.

Campaigns now store `template_bindings` separately from template definitions:

```json
{
  "body.1": {"source": "contact", "field": "full_name", "fallback": "Müşterimiz"},
  "body.2": {"source": "literal", "value": "YAZ20"},
  "header.media": {"source": "media_link", "value": "https://cdn.example.com/summer.jpg"},
  "button.0": {"source": "literal", "value": "summer"}
}
```

Keys must exactly match the selected template's input manifest. Supported values:
positional/named body and text-header variables, image/video/document header links
or media IDs, and positional dynamic URL button suffixes. Static footer, phone/URL
buttons and ordinary quick-reply buttons do not require parameters. Custom
quick-reply payloads, authentication/OTP, carousel, catalog, location, Flow and
special-purpose template components are not implemented; unknown types fail closed.
Structured currency/date parameters are not exposed; supply formatted text instead.

Contact bindings allow only full_name, phone, and email. Missing fields use the
explicit fallback or fail that recipient before any Meta call. Media references
must be actual send-time links/IDs, not creation examples or resumable-upload handles.
Media availability, supported MIME/size, and approved-template compatibility still
require provider checks in the deferred integration phase.

The UI loads manifests from the server instead of maintaining a second template
parser. It persists values with draft/send requests. Draft listing/editing and
history/controller integration are implemented in source. Existing campaigns receive `{}`;
static templates can still send, but variable templates require values before send.

## Durable queue deployment (implementation incomplete; not yet verified)

`20261030092000_campaign_dispatch_queue.sql` introduces `campaign_dispatches` and
service-only worker RPCs. See [CAMPAIGN_EXECUTION.md](CAMPAIGN_EXECUTION.md) for the
protocol, unknown-send handling and required integration order. This is an incremental
foundation: do not deploy it alone as the finished campaign upgrade. Apply migrations
in timestamp order, including `20261030093000_whatsapp_connections.sql`,
`20261030094000_campaign_worker_integration.sql`, and
`20261030095000_template_account_sync.sql`. The replacement enqueue endpoint,
tenant connection resolver, worker and template sync are implemented in source;
client history/controller and campaign receipt integration are implemented in source.
Apply `20261030100000_campaign_draft_identity.sql` before releasing the matching
client and enqueue endpoint. It adds draft revisions, the save RPC and revokes direct
client campaign writes. Older clients that insert campaigns directly must be upgraded.

When the complete implementation reaches verification:

1. Configure the connection secrets documented in `WHATSAPP_CONNECTIONS.md`.
   Generate a separate random `CAMPAIGN_WORKER_SECRET` (32–256 characters); do not
   reuse a service-role key, put it in Flutter, or commit it to source control.
2. Deploy `campaign-worker`, `send-campaign`, `sync-templates`,
   `campaign-template-inputs` and `manage-whatsapp-connection` with shared modules.
   Only the worker disables platform JWT verification; it verifies its dedicated
   bearer secret before reading input or touching the queue. User endpoints still
   authenticate sessions and authorize tenant permissions.
3. In Supabase Vault, store the HTTPS project base URL as `project_url` (no trailing
   slash) and the same worker secret as `campaign_worker_secret`. Install/enable
   pg_cron and pg_net and apply `supabase/ops/schedule_campaign_worker.sql` manually.
   This optional operations script replaces only its own named schedule.
4. Connect the intended WhatsApp account and synchronize templates before enqueueing.
   Legacy unlinked rows remain preserved; ambiguous identities require selecting a
   freshly synced scoped template. The campaign form now selects its sending account;
   template sync/creation still need their full multi-account management UI.
5. Monitor cron/pg_net invocation failures and queue age/blocked/unknown counts.
   A healthy HTTP invocation is not proof of recipient delivery. Never automatically
   replay an unknown dispatch. No schedules or sends have been enabled by this work.

The new campaign/template composite foreign key rejects new cross-tenant references
but is initially NOT VALID to preserve historical data. Before release, audit:

```sql
select c.id, c.tenant_id, c.template_id
from public.campaigns c
join public.templates t on t.id = c.template_id
where c.tenant_id <> t.tenant_id;
```

Review any mismatches and repair their intended references before running
`alter table public.campaigns validate constraint campaigns_template_tenant_fk`.
Do not auto-delete campaigns or guess their intended template. Legacy jobs become
read-only to clients; historical sends are not replayed into the new queue.

## Inbound conversation deployment dependency

Apply `20261030102000_whatsapp_inbound_conversations.sql` after the webhook ledger
migration, and deploy its matching `webhook-worker` during the eventual complete
upgrade. It adds account-scoped conversations, provider message deduplication,
protected customer timestamps and private bot input jobs. The shared inbox receives
updates through its existing messages/conversations realtime subscriptions.

Legacy conversations retain null connection/customer identity. New verified messages
create scoped threads even when an older unscoped thread exists for that contact.
Historical mapping needs operator review of the actual business number. The migration
does not infer the default number for historical threads. The human sender and
read/handoff RPCs and scoped bot worker are now implemented in source.
See [WEBHOOKS.md](WEBHOOKS.md) and [AI_WORKER.md](AI_WORKER.md).

The new tenant foreign keys are initially `NOT VALID` to preserve old rows. Before
release, review the following results in the isolated upgrade environment, repair
the intended references, and validate both constraints.

```sql
select c.id, c.tenant_id, c.contact_id, p.tenant_id as contact_tenant
from public.conversations c
join public.contacts p on p.id = c.contact_id
where c.tenant_id <> p.tenant_id;

select m.id, m.tenant_id, m.conversation_id, c.tenant_id as conversation_tenant
from public.messages m
join public.conversations c on c.id = m.conversation_id
where m.tenant_id <> c.tenant_id;

alter table public.conversations validate constraint conversations_contact_tenant_fk;
alter table public.messages validate constraint messages_conversation_tenant_fk;
```

`supabase/tests/whatsapp_inbound_conversations.sql` is a transactional fixture for the
later verification phase. Include concurrent workers, duplicate webhook delivery,
disconnect races and upgrade data in that phase. Static grammar parsing cannot prove
the behavior of these database privileges or transactions.

## Deferred verification commands

The AI context foundation is `20261101090000_bot_context.sql`. Deploy it as part of
the complete AI worker integration described in [AI_WORKER.md](AI_WORKER.md).
It adds settings/knowledge bounds requiring historical validation, exact input
identity and context versions. New bot settings default to inactive, and the matching
Flutter client stops implicitly saving defaults when the settings page opens.
The worker integration now follows in `20261101091000_bot_worker.sql`. Deploy the
matching worker/shared modules and configure its dedicated secret, OpenAI key,
model allowlist and default token cap as documented in `AI_WORKER.md`. Its optional
Vault/cron setup is `supabase/ops/schedule_bot_worker.sql`. Usage periods currently
follow UTC calendar months. Subscription-driven per-tenant overrides remain pending.

The inbox sender upgrade requires `20261030104000_inbox_dispatch_queue.sql`, the
updated Flutter client, `send-message` and `inbox-worker`. It revokes direct message
writes and limits direct conversation updates to tags. Deploy the updated receipt
worker and shared delivery module alongside both sender workers. Configure the
dedicated worker secret and manual scheduler described in
[INBOX_EXECUTION.md](INBOX_EXECUTION.md). This upgrade requires a coordinated client
release because sends now require stable request IDs and return queued state.

The inbox lifecycle upgrade also requires `20261030103000_inbox_lifecycle_actions.sql`
and its matching Flutter client. It revokes direct handoff writes and guards direct
conversation lifecycle edits. Deploy the client with `mark_conversation_opened` and
`request_conversation_handoff` RPC usage, including the explicitly named tenant
foreign key in the handoff list query. Existing clients using direct writes need
this coordinated upgrade.

Handoff requires both inbox and handoff permissions, matching the earlier two-write
workflow. IDs originate on the client and remain stable across retries. Employee
identity, role and timestamps originate on the server. No handoff note is copied
into the audit log. The shared unread reset remains a conversation-wide opened
marker. Per-agent cursors and provider read acknowledgements remain pending.

Audit historical handoff references and validate the new constraint after repair.

```sql
select h.id, h.tenant_id, h.conversation_id, c.tenant_id as conversation_tenant
from public.handoff_requests h
join public.conversations c on c.id = h.conversation_id
where h.tenant_id <> c.tenant_id;

alter table public.handoff_requests validate constraint handoff_conversation_tenant_fk;
```

Authored lifecycle fixtures are `supabase/tests/inbox_lifecycle_actions.sql` and
`test/inbox_lifecycle_test.dart`. Run them in the later verification phase, including
concurrent handoff/inbound events, lost responses, revoked permissions and tenant
switching while a request is pending. They have not been executed.

Apply the connection foundation migration `20261030093000_whatsapp_connections.sql`
in order as part of the eventual complete deployment. Configuration and verification
requirements are in [WHATSAPP_CONNECTIONS.md](WHATSAPP_CONNECTIONS.md). Do not ship
the connection endpoint with remaining global-credential senders as a finished
multi-tenant integration. The old unsigned webhook has now been replaced by a signed
receiver. Inbound inbox materialization is implemented in source and the replacement
bot consumer remains pending.

Test suites are authored but not executed at the owner's request. During verification,
run `supabase/tests/campaign_audience.sql` against an isolated migrated database.
It uses a transaction and rolls its fixture changes back. Full RLS adversarial tests,
upgrade tests and provider integration checks remain required before production.

Additional authored suites (do not run until the agreed verification phase):

```text
deno test supabase/functions/_shared/template_parameters_test.ts
flutter test test/widget_test.dart
```

Also execute `supabase/tests/campaign_dispatch_queue.sql` on an isolated migrated
database in that phase. It is transactional and authors no network sends. The queue
migration and SQL fixture were grammar-parsed with pglast 8.7 during implementation;
this does not validate PostgreSQL privileges, constraint behavior or concurrency.

Static-only checks used during implementation:

```text
dart analyze lib/features/campaigns test/widget_test.dart
npx --yes --package typescript@5.9.3 tsc --project supabase/functions/_shared/tsconfig.parameters.json
```

The isolated TypeScript config checks the pure builder without inheriting unrelated
parent-folder Node types. New connection entrypoints/helpers and authored Deno cases
were additionally type-checked with the temporary `npx deno` tool (2.9.6). Type
checking does not execute suites or prove Edge runtime/provider integration.
