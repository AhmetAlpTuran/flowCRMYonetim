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

## Online payment with iyzico (Phase 3b, `20261109100000_iyzico_billing.sql`)

Administrators pay from the Abonelik screen on Android. On iOS the screen shows plans and
usage but no purchase buttons, because of the app stores' purchase rules; cancellation still
works there.

1. **Billing details.** "Fatura bilgileri" (`save_billing_profile`, admins) stores the details
   iyzico requires: name, surname, email, mobile (normalized to +90…), a 10-11 digit Turkish ID
   or tax number, billing address and city, plus an optional company name and tax office.
2. **Checkout.** "Satın al" calls the `billing` Edge Function (`checkout`). It runs
   `begin_billing_checkout`, which checks the caller is an admin, the plan has an iyzico
   pricing plan code for the period, billing details exist, there is no live online
   subscription, and fewer than 10 checkouts were started this hour. It then initializes an
   iyzico subscription checkout form and returns the payment page URL.
3. **Payment page.** The app opens `docs/odeme/?oturum=<checkout id>` (GitHub Pages) in the
   browser. The page loads that checkout's iyzico form from `iyzico-gateway/checkout` and
   renders it. Card details are entered only in iyzico's form.
4. **Callback.** iyzico posts the customer back to `iyzico-gateway/callback/<checkout id>`. The
   gateway reads the result from iyzico by token and never trusts the browser.
   `complete_billing_checkout` then activates the subscription: plan, period,
   `provider = iyzico` and references, paid until a period plus 3 days. The browser is
   redirected to `docs/odeme/sonuc/` (`basarili` / `basarisiz` / `beklemede`). If iyzico
   could not be reached, the checkout stays open. The app re-checks it (`billing` → `refresh`)
   when the Abonelik screen opens or the app returns from the browser.
5. **Webhooks.** `iyzico-gateway/webhook` accepts only requests whose `X-IYZ-SIGNATURE-V3`
   matches. The value is `hex(HMAC-SHA256(secretKey, merchantId + secretKey + eventType +
   subscriptionReferenceCode + orderReferenceCode + customerReferenceCode))`.
   - `subscription.order.success` extends the paid period.
   - `subscription.order.failure` moves the subscription to `past_due` with a 7-day grace.
   - Each event applies once (`billing_events`). Events for an unknown subscription are kept
     with `applied = false` for review.
6. **Change plan / cancel.** These are `billing` actions `change_plan` and `cancel`. A plan
   change uses iyzico upgrade with `NOW`, which needs the same product and billing interval;
   switching between monthly and yearly is not offered. Cancel stops renewals, and the plan
   stays until the paid period ends.

### Owner setup (sandbox first)

1. Open an iyzico merchant account. Sandbox: https://sandbox-merchant.iyzipay.com.
2. In the merchant panel, create one product ("Flow CRM") with a TRY pricing plan for each
   plan and period. Use the same amounts as `billing_plans`, and keep monthly and yearly
   plans in the same product. Then store the reference codes:
   `update public.billing_plans set iyzico_monthly_plan_code = '<code>', iyzico_yearly_plan_code = '<code>' where key = 'pro';`
   A plan without a code shows no purchase button.
3. Set the Edge Function secrets `IYZICO_API_KEY`, `IYZICO_SECRET_KEY`, `IYZICO_MERCHANT_ID`,
   `IYZICO_BASE_URL` (sandbox or `https://api.iyzipay.com`) and `BILLING_PAGE_URL`. Then deploy
   `billing` and `iyzico-gateway`. `iyzico-gateway` runs without JWT verification
   (`supabase/config.toml`).
4. In `docs/odeme/index.html`, set `flow-functions-url` to
   `https://<project-ref>.supabase.co/functions/v1`, and publish GitHub Pages.
5. In the iyzico panel (Settings → Merchant Settings → Merchant Notifications), set the
   notification URL to `https://<project-ref>.supabase.co/functions/v1/iyzico-gateway/webhook`.
   Then email entegrasyon@iyzico.com to enable the V3 webhook signature; unsigned
   notifications are rejected.
6. Test with iyzico's sandbox test cards: a successful payment, a failed card, a renewal
   (or the order retry endpoint), a plan change and a cancellation.

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
- Phase 3b:
  - SQL fixture `iyzico_billing.sql` covers billing details validation and normalization,
    checkout preconditions, token-bound idempotent completion, a declined payment,
    webhooks (renewal, failure grace, duplicates, unmatched), plan change and cancellation.
  - Deno tests `iyzico_test.ts` check the IYZWSv2 header and the V3 webhook signature
    against vectors computed independently in Python. They also cover the request and
    response mapping and the URLs.
  - 9 Flutter tests.
  - A local end-to-end run on the Edge runtime against a fake iyzico that verifies every
    request's signature:
    - checkout refused without billing details, then the payment page loads the form
    - the callback activates Profesyonel, and a forged token does not
    - a badly signed webhook gets 401, and the signed one applies once
    - plan change and cancel work
  - **Runtime unverified** until sandbox keys exist:
    - real iyzico responses: form rendering, callback and webhook payloads, and in
      particular the merchantId part of the webhook signature, which iyzico's example
      payload does not carry
    - upgrade proration
