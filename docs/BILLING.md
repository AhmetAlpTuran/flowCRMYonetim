# Plans, subscriptions and limits (roadmap Phase 3)

Migration: `supabase/migrations/20261109090000_billing_plans.sql`. App: **Abonelik**
(administrators only) shows the plan, its status, this month's usage against the limits,
and the public plans.

## Plans (starting prices, TRY per month, VAT excluded)

| Key | Name | Monthly | Yearly | Users | Numbers | Bots | AI tokens / month (≈ replies) | Campaign messages / month |
|---|---|---|---|---|---|---|---|---|
| `starter` | Başlangıç | 1.490 | 14.900 | 2 | 1 | 1 | 3M (≈ 1.000) | 1.000 |
| `pro` | Profesyonel | 3.490 | 34.900 | 5 | 2 | 3 | 15M (≈ 5.000) | 10.000 |
| `business` | İşletme | 7.990 | 79.900 | 15 | 5 | 11 | 60M (≈ 20.000) | 50.000 |
| `pilot` | Pilot (not public) | 0 | – | 50 | 10 | 11 | 15M | 100.000 |
| `expired` | Süresi doldu (not public) | 0 | – | 0 | 0 | 0 | 0 | 0 |

These are defaults to test during the pilot. Change them with plain SQL, e.g.
`update public.billing_plans set monthly_price_try = 2990 where key = 'pro';`.
"Bots" counts the main bot plus extra bots. A reply is estimated at 3,000 tokens.

## Subscriptions

`tenant_subscriptions` has one row per business: `plan_key`, `status`, `trial_ends_at`,
`current_period_end`, `grace_ends_at`, and the provider references used by the
payment integration. Clients can read their own row (administrators) but never write it.

- New businesses (`create_business`) start a **14-day Profesyonel trial**.
- Businesses that existed before billing were given a `pilot` subscription. A business
  without any row (created directly by the owner) is treated as Pilot as well.
- The status that applies is computed from timestamps, so no scheduled job is needed:
  - `trialing` until `trial_ends_at`.
  - `past_due` until `grace_ends_at` (or the period end).
  - `canceled` until `current_period_end`.
  - After that, `expired`.

## What the limits do

All limits are enforced in the database, whatever path the write takes. A refusal uses
SQLSTATE `P0020` with hint `plan_limit:<kind>`, and Edge Functions answer HTTP 402
`plan_limit`. The app shows Turkish guidance that points to Abonelik.

| Limit | Where |
|---|---|
| Users (seats) | `tenant_memberships` insert trigger (invite acceptance, join approval, direct adds); `create_tenant_invite` checks early. Changing an existing member is never blocked. |
| WhatsApp numbers | `whatsapp_connections` insert trigger (`save_whatsapp_connection`; reconnecting the same number is allowed) |
| Bots | `bot_profiles` insert trigger (main bot + extra bots) |
| Campaign messages / month | statement trigger on `campaign_dispatches`: a campaign that would exceed the month's allowance is refused whole (`tenant_message_usage`) |
| AI tokens / month | `prepare_bot_reply`. Precedence: an explicit `tenant_ai_limits` row, then the subscribed plan's allowance, then `AI_MONTHLY_TOKEN_LIMIT` (only for businesses without a subscription). Over the allowance, the bot hands off. |

When a subscription lapses (`expired`), existing members, numbers and bots stay, but
nothing new can be added. Bots hand off (0 tokens), campaigns are refused, and agents keep
replying in the inbox. Contacts are not limited, because inbound chats create them
automatically.

## Owner operations (SQL editor, service role)

```sql
-- Put a pilot business on a paid plan for a month (manual billing):
update public.tenant_subscriptions
   set plan_key = 'pro', status = 'active', provider = 'manual', billing_period = 'monthly',
       current_period_end = now() + interval '1 month', trial_ends_at = null, updated_at = now()
 where tenant_id = '<tenant id>';
-- Extend a trial by a week:
update public.tenant_subscriptions set trial_ends_at = trial_ends_at + interval '7 days'
 where tenant_id = '<tenant id>' and status = 'trialing';
```

## Changing plans from the app

The upgrade button opens `--dart-define=BILLING_URL` (a web page outside the app stores'
purchase flows). It is never shown on iOS, and without a URL the screen shows
`SUPPORT_EMAIL`. Payment collection through iyzico is the next step (Phase 3b). Before
store submission, confirm with the store policies that this B2B setup qualifies.

## Not covered (owner decisions)

- **Prepaid message credits:** Meta bills each business's own WhatsApp account directly
  today. Reselling credits requires becoming a Meta Solution Partner with a credit line.
- **e-Arşiv invoices:** needs an invoicing provider account (for example Paraşüt).

## Verified

- SQL fixture `billing_plans.sql`. It covers:
  - the trial on business creation, and the overview permissions
  - every limit and its paths: upsert of an existing member, number reconnect, the
    bot count, and a refused campaign leaving no rows or usage
  - the AI allowance and the expired state
  - grace and cancelled periods, and the Pilot fallback
- 6 Flutter tests.
- A live PostgREST run: a confirmed user created a business, which got the trial, and
  read the overview.
