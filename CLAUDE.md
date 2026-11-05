# Flow CRM (WPapp)

Multi-tenant WhatsApp support, AI automation and marketing SaaS. Flutter client +
Supabase backend (Postgres migrations, RLS, Deno Edge Functions, pg_cron workers).
Started as a university Mobile Programming project; now being taken to a paid product.

`DEVELOPMENT_STATUS.md` is the source of truth for progress, milestones and known
risks. Read it before starting work and append a dated milestone log entry after.

## Layout

- `lib/features/<feature>/{data,models,providers,screens,widgets}`: feature-first Flutter.
  Features: app, shell, tenancy, onboarding, users, connections, contacts, inbox, handoff,
  campaigns, templates, bot, knowledge, catalog, account, billing, dashboard (`dashboard_metrics` RPC).
- `lib/config/supabase_config.dart`: Supabase URL/anon key from `--dart-define`
  (`SUPABASE_URL`, `SUPABASE_ANON_KEY`); defaults target the local `supabase start` stack.
  Android emulator: `--dart-define=SUPABASE_URL=http://10.0.2.2:54321`.
- `supabase/functions/.env.example`: every Edge Function secret (names only).
- `docs/ROADMAP.md`: the approved plan to finish, monetize and publish.
- `lib/core/request_id.dart`: shared stable UUIDs for idempotent client requests.
- `supabase/migrations/`: additive, timestamped SQL. `supabase/tests/`: SQL fixtures.
- `supabase/functions/`: Edge Functions (`*-worker` = scheduled background workers,
  `whatsapp-webhook` = HMAC-verified Meta receiver, `_shared` = common helpers).
  `send-campaign` is the current authenticated campaign enqueue endpoint (sends happen
  in `campaign-worker`). `bot-reply` is only a legacy alias of the webhook URL.
  `billing` (admins) and `iyzico-gateway` (public: payment page, callback, signed webhooks)
  run iyzico subscriptions; plan limits raise SQLSTATE `P0020` (`docs/BILLING.md`).
  `health` serves `ops_health()` to uptime monitors (`docs/OPERATIONS.md`).
- `supabase/ops/schedule_*.sql`: cron/Vault scheduler scripts for each worker (webhook,
  inbox, campaign, bot, media, knowledge); run them manually per environment.
- `docs/`: per-area design and backend setup notes. `docs/gizlilik`, `docs/privacy` and
  `docs/odeme` (payment page) are published with GitHub Pages. `DESIGN.md` / `UX-CONTRACT.md`:
  theme and UI behavior contract.
- `AppServer/` (NestJS) is git-ignored and unused by the app (`useEdgeFunctions = true`).
- `WPAPI/`: Meta Postman collections, reference only.

## Stack and commands

- Flutter (Dart `>=3.3.0`), Riverpod 2, supabase_flutter. Deno for Edge Functions.
- `flutter pub get`, `flutter analyze`, `flutter test`
- `deno check supabase/functions/<name>/index.ts`
- Local backend: `supabase start`, `supabase db reset` (local only), `supabase functions serve`

## Architecture rules

- Server owns truth: identity, timestamps, permissions and state transitions go through
  RPCs/Edge Functions. Direct client writes to lifecycle tables are revoked; don't add new ones.
- Every query and FK must be tenant-scoped (composite tenant references). Never trust
  UI permissions alone; enforce in RLS/RPC.
- Marketing sends only to `consented_contacts` rows without `opted_out_at`; consent is
  written only through `set_marketing_consent`/`import_contacts` with a recorded basis.
- Sends go through durable queues with fenced claims. An uncertain provider outcome
  is never blindly retried. Clients retain one immutable request ID on uncertain results.
- WhatsApp tokens live encrypted per tenant connection; no global credentials.
- Riverpod controllers own remote state; invalidate on tenant/session change.
- Handle loading, error and narrow-layout states per `UX-CONTRACT.md`.

## Working rules

- Migrations are additive only. Never reset or drop data as an upgrade path.
- Never commit secrets (`supabase/functions/.env` is ignored). Credentials exposed during
  earlier debugging must be rotated before deployment.
- Don't send real WhatsApp messages, provision paid resources or charge subscriptions
  as a development check.
- Write tests with each feature and run the suites before committing:
  `flutter test --timeout 60s`, `scripts/run_sql_tests.sh` (needs `supabase start`), and Deno
  via Docker when it isn't installed:
  `docker run --rm -v "<repo>/supabase:/app/supabase" -w /app denoland/deno:2.9.8 deno check supabase/functions/*/index.ts`
  (CI pins the same Deno 2.9.8; add `deno test --allow-env --allow-net=127.0.0.1 supabase/functions/_shared`).
  Label anything not exercised at runtime (live Meta/OpenAI calls) as "runtime unverified".
- In widget tests, build `SupabaseClient` with `AuthClientOptions(autoRefreshToken: false)`,
  give fake `http.Response`s `request: request`, and don't await `client.dispose()`.
  `functions.invoke` never completes inside `testWidgets` (it encodes on an isolate the
  fake clock never runs): test its HTTP mapping in a plain `test`, and override the
  repository provider with a fake in widget tests. Smoke runs against the local stack
  must delete their rows afterwards; SQL fixtures assume empty queues.
- Commit messages: Conventional Commits, `type(scope): summary` (scopes: campaigns,
  inbox, ai, support, auth, tenancy, webhooks...). Stage explicit paths only.
- Commit `pubspec.lock` together with any dependency change (CI pins Flutter 3.41.2).
- The owner writes in Turkish or English; UI strings are Turkish.
