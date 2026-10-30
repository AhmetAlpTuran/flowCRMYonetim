# Backend setup and upgrade notes (in progress)

The SaaS backend is not ready for production deployment. This guide grows with each
milestone. No migrations have been applied automatically by this implementation work.

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

Preview is live: contacts may change before dispatch. A future campaign snapshot
milestone will freeze the recipients at enqueue time. Current sender still has its
legacy 100-recipient cap; queue/pagination work remains before large campaigns ship.

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
durable dispatch are subsequent milestones. Existing campaigns receive `{}`;
static templates can still send, but variable templates require values before send.

## Durable queue foundation (integration pending)

`20261030092000_campaign_dispatch_queue.sql` introduces `campaign_dispatches` and
service-only worker RPCs. See [CAMPAIGN_EXECUTION.md](CAMPAIGN_EXECUTION.md) for the
protocol, unknown-send handling and required integration order. This is an incremental
foundation: do not deploy it alone as the finished campaign upgrade. The enqueue
endpoint, per-tenant connection resolution, scheduler/worker and UI progress must
be deployed together after their implementation milestones.

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

## Deferred verification commands

Apply the connection foundation migration `20261030093000_whatsapp_connections.sql`
in order as part of the eventual complete deployment. Configuration and verification
requirements are in [WHATSAPP_CONNECTIONS.md](WHATSAPP_CONNECTIONS.md). Do not ship
the connection endpoint with the legacy unsigned webhook or global-credential
senders as a finished multi-tenant integration.

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
