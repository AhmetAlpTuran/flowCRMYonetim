# Flow CRM roadmap: finish, monetize and publish

## Context
Flow CRM is a multi-tenant WhatsApp support, AI bot and marketing SaaS (Flutter + Supabase).
About 6 weeks of backend work (queues, webhooks, AI worker, support workflows) exists in source
but has **never been run**. The owner now also wants **custom bots that act on business data**:
for example a room-rental business whose bot checks availability and books dates, or a used-car
dealer whose bot searches stock and sends photos.

Decisions made:
- Market: Turkey first (TRY, iyzico/PayTR, KVKK, Turkish UI).
- Launch: a pilot with 3–5 real businesses (for example the car dealer and a rental business), then a public launch.
- Platforms: Android + iOS first, web app later. All AI/WhatsApp workers already run on Supabase
  (Edge Functions + pg_cron), so the server side is the same for every client.
- Bot data: built-in tables are the source of truth. Google Sheets sync is **future work, not in
  this plan**; the schema only leaves room for it.

## What exists vs. what is missing (from codebase exploration)
| Area | Today | Gap |
|---|---|---|
| AI bot | One bot per tenant (`bot_settings` keyed by `tenant_id`); one OpenAI Responses call with `tools: []` (`supabase/functions/_shared/ai_reply.ts`); strict JSON reply schema; lexical full-text knowledge search, top 5 (`bot_reply_context` in `20261101090000_bot_context.sql`); token metering (`tenant_ai_usage`, `prepare_bot_reply`, `settle_bot_usage`); many auto-handoff paths | No tool calling, no business data, plain-text knowledge only, no file upload, no embeddings, only one bot per tenant |
| WhatsApp out | Text messages (`inbox-worker`, hard-coded `type:"text"`), template campaigns (`campaign-worker`, `_shared/template_parameters.ts`) | No images or documents, no interactive buttons or lists, no Flows, no catalog messages |
| WhatsApp in | Every type stored raw in `provider_content`; the bot only reacts to text, button and interactive replies (title only) | No media download, the bot ignores interactive reply ids |
| Connections | Manual token entry via `manage-whatsapp-connection`, AES-GCM encrypted, several numbers per tenant | No Flutter screen, no Embedded Signup; `submit-template` and `upload-template-media` still use the global token |
| Tenancy | RLS with `user_has_permission`, roles, memberships, join requests | No self-service business creation, invites never emailed, no password reset |
| Contacts | `contacts` + `consented_contacts` with tags | No contacts screen, no CSV import, no opt-out field |
| App | Inbox, handoff, campaigns, templates, bot and knowledge screens all work against Supabase | Dashboard is a mock; no push notifications; app id `com.example.wpapp`; release build signed with the debug key; hard-coded localhost config |
| Billing | Only AI token caps | Plans, payments, entitlements, message credits |
| Ops | `supabase/ops/schedule_*.sql` scripts exist but are not active | No deployment, CI, monitoring or backups |

## Revenue model (to be tested during the pilot)
1. **Monthly subscription tiers** (Başlangıç / Profesyonel / İşletme, roughly Starter / Professional / Business). The plan sets the number of agent seats,
   WhatsApp numbers, bots, contacts and included AI replies.
2. **Message credit wallet.** Meta charges per template message. Sell prepaid credits with a margin,
   which is the standard model for WhatsApp providers. This is recurring revenue that grows with each customer's usage.
3. **AI reply packs** on top of the plan's allowance. Metering already exists (`tenant_ai_usage`).
4. **Paid industry bot packs.** These are ready-made bots that charge per pack:
   - **Rental & Booking**: rooms, villas, appointments.
   - **Auto Dealer** (Oto Galeri): stock search, photos, test-drive booking, trade-in lead form, financing lead.
   - **Clinic / Salon appointments**.
   - **Restaurant orders / reservations**.
5. **Booking deposits through WhatsApp.** The bot sends an iyzico payment link to confirm a booking,
   and Flow CRM takes a small commission on each deposit.
6. **Add-ons**: extra numbers and seats, appointment reminders
   (utility templates that also use message credits), and white-label or agency accounts that manage many businesses.
7. **Setup service**: a one-time paid onboarding (WhatsApp verification, bot set-up and data import)
   for businesses that are not technical.

## Phase 0: Verify what exists (weeks 1–3, must come first)
- Start local Supabase (`supabase start`, `supabase db reset`). Fix the 29 migrations with additive
  fixes only. Run `supabase/tests/*.sql`, `flutter test` and `deno check` on every function.
- Rotate all leaked credentials. Write `supabase/functions/.env.example` with variable names only
  (taken from the docs: `META_APP_SECRET`, `WHATSAPP_CREDENTIAL_KEYS`, the `*_WORKER_SECRET`s, the `OPENAI_*` vars, and so on).
- Replace `lib/config/supabase_config.dart` with `--dart-define` values (local, staging, prod). Delete
  `lib/config/app_server_config.dart`, the legacy `bot-reply` and `send-campaign` functions, the unused mock repositories, and stop relying on the ignored `AppServer/`.
- Create a hosted Supabase **staging** project and turn on the four `supabase/ops/schedule_*.sql` worker schedules.
  Test end to end with a Meta test number: inbound message → bot reply → handoff → campaign → delivery receipts.
- Audit service-role queries for missing tenant checks, and validate the `NOT VALID` foreign keys.
- Add GitHub Actions to run `flutter analyze`, `flutter test`, `deno check` and the migrations against a throwaway database.

## Phase 1: Product gaps the pilot needs (weeks 3–7)
- **Onboarding**: self-service business creation (an RPC that creates the tenant, the admin membership and default
  `features`); invite emails with an accept flow through `tenant_invites`; password reset; a first-run setup checklist.
- **WhatsApp connection screen** in Flutter, using the existing `manage-whatsapp-connection` with manual
  tokens for the pilot. Port `submit-template` and `upload-template-media` to per-tenant connections
  (reuse `resolveConnection` from `_shared`).
- **Push notifications** (FCM/APNs) for new messages and handoffs. Without them, a mobile-first app misses
  customers. Add a `device_tokens` table, and have `materialize_whatsapp_message` or handoff send the push through a small worker.
- **Media**: download inbound media to a private Storage bucket and show it in `chat_screen.dart`;
  enable sending images and documents through `inbox_dispatches` (a new payload type in `inbox-worker`).
- **Contacts screen**: list, edit, tags, CSV/Excel import, opt-out and a record of how consent was given.
- **Real dashboard**: replace `MockDashboardRepository` with SQL RPCs (message volume, bot vs. human
  share, first-response and resolution times from `support_episodes`, campaign results).
- **Store readiness**: new app id (for example `com.flowcrm.app`), name and icons, release signing,
  in-app account deletion (an Apple requirement), privacy policy link.

## Phase 2: Custom bot platform (weeks 6–12)
**2a. Tool calling in the AI worker**
- In `_shared/ai_reply.ts`, change `prepareAiRequest`, `generateAiReply` and `parseAiReply` to call the model in a loop. The loop
  handles `function_call` items, runs the tool and sends back `function_call_output`. It has a maximum number of turns, and usage is
  settled across every turn in `settle_bot_usage`. Raise the 120s lease in `prepare_bot_reply`.
- Add a new `_shared/bot_tools/` registry with typed tools. Each tool calls a service-only SQL RPC
  that is tenant-scoped and idempotent (key = job id + tool call id), and is logged to `tenant_audit_events`.
- Extend the reply schema and the checks in `complete_bot_reply` with a `tool_answer` reason and tool-result ids.
  Replace the "you have no tools" instruction.

**2b. Business data model (built-in, the source of truth)**
- `resource_types`: tenant-defined item types (Room, Vehicle) with a JSON field schema.
- `resources`: the items, with jsonb attributes, photos in Storage and a status.
- `bookings`: a `tstzrange` column with a `btree_gist` exclusion constraint, so two bookings
  for the same item can never overlap.
- Booking states go `hold` (expires after N minutes) → `confirmed` after the customer taps "Onayla" (Confirm)
  on an interactive button, then optionally after the deposit is paid → `cancelled`.
- `leads`: test-drive requests, trade-in requests, financing interest.
- Flutter screens: a resource list and editor, a booking calendar, and a leads list.

**2c. Industry packs** (a pack is a preset of resource type, tools, prompt and templates)
- Rental: `check_availability`, `create_booking_hold`, `confirm_booking`, `cancel_booking`,
  `send_payment_link`.
- Auto Dealer: `search_inventory` (brand, model, year, km, price range), `send_listing` (photos and
  details), `schedule_test_drive`, `create_lead`. Stock can be imported from CSV/Excel or a dealer XML feed.

**2d. External data sync: deferred, keep the door open**
- Do **not** build Google Sheets (or any sheet) integration now.
- Design for it later: `resources` and `bookings` get nullable `external_source` / `external_id` /
  `external_synced_at` columns, and all writes go through RPCs, so a future sync worker can plug in
  without schema changes. The database stays authoritative for availability.
- CSV/Excel file import (Phase 1 contacts, 2c inventory) covers the pilot's data entry needs.

**2e. Richer WhatsApp messages**
- Interactive buttons and lists, and images with captions, as new outbound types in `inbox-worker`.
- Pass `button_reply` / `list_reply` ids and `nfm_reply.response_json` to the bot context.
- Later: WhatsApp Flows for date pickers and lead forms.

**2f. Documents and better answers**
- A `knowledge_documents` table and bucket, plus an extraction worker that turns docx, pdf and xlsx files into chunks.
- Add pgvector and hybrid search in `bot_reply_context`, keeping full-text search as the fallback.

**2g. Multiple bots per tenant**
- Give each bot its own id, change `bot_settings` from one row per tenant to one row per bot, and assign a bot to each connection or route by keyword.
- Add a bot id to `bot_reply_jobs`, `claim_bot_reply`, `bot_reply_context` and `complete_bot_reply`.

## Phase 3: Payments and billing (weeks 10–14)
- `plans`, `subscriptions`, `entitlements` and `credit_ledger` tables. Every limit is enforced in
  the server RPCs that already exist: seats in membership writes, numbers in `save_whatsapp_connection`, messages in
  `enqueue_campaign` / `enqueue_inbox_message`, and AI usage by replacing `AI_MONTHLY_TOKEN_LIMIT` with the plan's allowance.
- iyzico subscription API with webhooks for renewal, failed payment and cancellation, plus a grace period. Credit top-ups and
  booking-deposit payment links go through iyzico as well.
- e-Arşiv invoices through an invoicing provider's API (for example Paraşüt).
- Do checkout on a **small web billing page**, not inside the app, so App Store and Play in-app
  purchase rules don't apply. Confirm the B2B exemption with the store policies before submission.

## Phase 4: Operations, compliance, Meta (runs alongside Phases 1–3)
- Supabase Pro (backups and point-in-time recovery) for production; error tracking for Flutter and functions;
  alerts on stuck queues, webhook failures and AI errors; a tested restore drill.
- Meta: Business Verification, register as a **Tech Provider**, App Review for
  `whatsapp_business_management`/`messaging`, and Embedded Signup before public launch.
- KVKK: privacy notice (aydınlatma metni), data-processing agreement for customer businesses, cross-border transfer
  paperwork (OpenAI, Supabase region), retention policy, and a check of whether VERBİS registration is required.
- Commercial messaging law 6563 (ticari elektronik ileti): keep proof of consent and support opt-out; confirm with a lawyer whether İYS (the national consent registry) applies to WhatsApp marketing.
- Store listings, a Turkish landing page, support email, terms of service.

## Phase 5: Pilot → launch
- Pilot (4–6 weeks): onboard 3–5 businesses by hand, measure bot resolution rate, booking/lead conversion and
  what customers are willing to pay. Fix issues weekly.
- Public launch: Embedded Signup and self-service plans live, store apps published, then the web app for desk agents.

## Critical files
- AI: `supabase/functions/_shared/ai_reply.ts`, `_shared/bot_execution.ts`,
  `supabase/functions/bot-worker/index.ts`, `20261101090000_bot_context.sql`, `20261101091000_bot_worker.sql`
- Messaging: `supabase/functions/inbox-worker`, `_shared/whatsapp_delivery.ts`,
  `20261030102000_whatsapp_inbound_conversations.sql` (`materialize_whatsapp_message`)
- Client: `lib/config/`, `lib/features/{bot,knowledge,dashboard,tenancy,users,inbox}`, `android/app/build.gradle*`
- New: migrations for resources, bookings, leads, plans and credits; `_shared/bot_tools/`, a document-extraction worker

## Future (not in this plan)
- Google Sheets / Calendar sync, WhatsApp Flows date pickers, web app for desk agents.

## Verification
- Each phase ends with SQL fixtures plus `flutter test` and `deno check` passing in CI, and a staging run with a
  Meta test number. Results are recorded in `DEVELOPMENT_STATUS.md`.
- Booking: concurrent hold attempts on the same room must produce exactly one booking (exclusion constraint test).
- Bot: a scripted conversation set per industry pack covering correct tool use, refusing to make up stock, and handing off when unsure.
- Billing: iyzico sandbox covering renewal, failure and cancellation; limits block sends when the plan is exceeded.
- Pilot exit criteria: no data leak between tenants, a bot resolution rate the pilot customers accept, and at least one paying pilot customer.
