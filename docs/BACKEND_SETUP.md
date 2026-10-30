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

## Deferred verification

Test suites are authored but not executed at the owner's request. During verification,
run `supabase/tests/campaign_audience.sql` against an isolated migrated database.
It uses a transaction and rolls its fixture changes back. Full RLS adversarial tests,
upgrade tests and provider integration checks remain required before production.
