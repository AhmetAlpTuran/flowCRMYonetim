# Owner checklist: from code to pilot to public launch

Everything here needs your accounts, money, signatures or legal judgment, so the code
cannot do it. Steps are in order. Each links to the doc with the details.

## A. Before the pilot (staging project)

1. **Rotate the leaked credentials.** The OpenAI and WhatsApp keys that were in
   `supabase/functions/.env` during early debugging must be revoked and replaced.
2. **Create a hosted Supabase project.** Start with staging, in an EU region (Frankfurt),
   and record the region in the privacy policy. Then deploy it in the order of
   [OPERATIONS.md](OPERATIONS.md) §1: migrations, secrets, functions, Vault and schedules.
3. **Email (Auth).** Configure an SMTP provider (Supabase's built-in mailer only reaches
   team members), the site URL and the Turkish templates. See
   [AUTH_ONBOARDING.md](AUTH_ONBOARDING.md).
4. **Meta.** Set up a developer app, add a WhatsApp test number, and configure the webhook
   (`…/functions/v1/whatsapp-webhook`, verify token, app secret). Then connect the number
   in the app's "WhatsApp" screen with a system-user token. See
   [WHATSAPP_CONNECTIONS.md](WHATSAPP_CONNECTIONS.md) and [WEBHOOKS.md](WEBHOOKS.md).
5. **OpenAI.**
   - Create an API key, set a monthly spend limit at OpenAI, and set
     `OPENAI_ALLOWED_MODELS`.
   - Run the industry pack evaluation and review any failures before pilots start. It
     runs `scripts/bot_eval.ts` with `EVAL_REPEAT=3`; see [AI_WORKER.md](AI_WORKER.md).
6. **GitHub Pages.**
   - Enable Pages (branch `main`, folder `/docs`).
   - Fill every highlighted placeholder in the privacy policy, and have a lawyer review it.
   - In `docs/odeme/index.html`, set the functions URL.
7. **iyzico sandbox.**
   - Open a merchant account, create the product and pricing plans, and store their codes
     in `billing_plans`.
   - Set the secrets and the notification URL, and email entegrasyon@iyzico.com to enable
     webhook signatures.
   - Test the sandbox flows: payment, failed card, renewal, plan change, cancel.
   - See [BILLING.md](BILLING.md).
8. **Monitoring.** Set `HEALTH_CHECK_SECRET` and point an uptime monitor at the `health`
   function. See [OPERATIONS.md](OPERATIONS.md) §2.
9. **Pilot businesses.** They sign up in the app (new ones get a 14-day trial). Move each
   pilot business to the plan you agreed, using the SQL in [BILLING.md](BILLING.md).
   Running `scripts/bot_eval.ts` again after you change a pack prompt is cheap.

## B. Before store submission

1. **Android.**
   - Generate the upload signing key and back it up forever, then create
     `android/key.properties`.
   - Set up the Play Console app, its data safety form and a demo reviewer account.
   - Make the Play Billing decision for online payment.
   - See [RELEASE.md](RELEASE.md).
2. **iOS.** Set the Apple Developer team in Xcode and create the App Store Connect app (bundle
   `com.flowcrm.app`), plus privacy labels and a demo account.
3. **Brand.** The app icon and launch screens use your "f" logo (`assets/brand`, regenerate
   with `scripts/brand_icons.py`). Still needed: store screenshots and Turkish descriptions.
4. **Push notifications.** Create a Firebase project (FCM, with APNs key for iOS). The app
   does not send pushes yet; the device-token table and a push worker get built once the
   project exists.

## C. Before the public launch

1. **Meta.**
   - Complete Business Verification and register as a Tech Provider.
   - Pass App Review for `whatsapp_business_management` and `whatsapp_business_messaging`,
     and set up an Embedded Signup configuration.
   - The self-service signup flow gets built once the configuration ID exists; until then,
     numbers are connected with tokens.
2. **iyzico production.** Switch to production keys and complete go-live. Choose an
   e-Arşiv invoice provider (for example Paraşüt).
3. **Supabase Pro.** Turn on point-in-time recovery, then run the restore drill in
   [OPERATIONS.md](OPERATIONS.md) §3.
4. **KVKK and commercial messaging.**
   - Check whether VERBİS registration is required.
   - Prepare a data processing agreement for businesses, the cross-border transfer
     notices (Supabase, Meta, OpenAI, iyzico) and a retention policy.
   - Get legal confirmation on whether İYS applies to WhatsApp marketing (law 6563).
5. **Pricing review.** Use pilot usage to set the final prices and decide whether to become a
   Meta Solution Partner, which prepaid message credits would require.

## D. Defaults chosen in code (change them freely)

| What | Default | Where |
|---|---|---|
| Plans and prices (TRY/month, VAT excl.) | Başlangıç 1.490, Profesyonel 3.490, İşletme 7.990; yearly = 10 months | `billing_plans` (SQL) |
| Trial | 14 days of Profesyonel for new businesses | `create_business` |
| Failed payment grace | 7 days | `apply_subscription_change` |
| AI allowance shown as replies | 3,000 tokens per reply | `tokensPerReply` (app) |
| Extra bots | up to 10 per business | `save_bot_profile` |
| Documents | 10 MB, 300 PDF pages, 50 per business | knowledge migration |
| Marketing stop words | STOP, RET, "abonelikten çık", "listeden çıkarın"… (bare "iptal" excluded) | `is_marketing_stop` |
| Booking hold | 15 minutes | `bot_create_booking_hold` |
| Online purchase in the app | on for Android, off for iOS | `ONLINE_PURCHASE` build flag |
