# Releasing Flow CRM to Google Play and the App Store

Updated 2026-11-06. App ID `com.flowcrm.app`, store name "Flow CRM". This ID cannot change
after the first release.

## One-time owner setup

### Android signing key (keep it safe forever)

Losing this key, or its password, means you can never update the app on Google Play.
Generate it once and back it up outside the repository (password manager plus an
offline copy):

```bash
keytool -genkey -v -keystore ~/flowcrm-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `android/key.properties` (git-ignored; never commit it):

```properties
storePassword=<the keystore password>
keyPassword=<the key password>
keyAlias=upload
storeFile=C:/Users/<you>/flowcrm-upload.jks
```

Without this file, release builds are signed with the debug key and Google Play rejects
them. Enrol in Play App Signing when creating the app in Play Console.

### iOS

In Xcode (`ios/Runner.xcworkspace`), select your Apple Developer team under Signing &
Capabilities; the bundle ID is already `com.flowcrm.app`. Create the app with that
bundle ID in App Store Connect.

### Store listing requirements

- **Privacy policy URL** (both stores) — the policy lives in `docs/gizlilik/index.html`
  (Turkish, prevails) and `docs/privacy/index.html` (English). Before publishing, replace
  every highlighted placeholder (company name, address, MERSİS, KVKK/KEP addresses, hosting
  region, email provider, backup retention, dates) and have a lawyer review it. To host it
  free: GitHub repository Settings > Pages > "Deploy from a branch", branch `main`, folder
  `/docs`. It is then served at
  `https://ahmetalpturan.github.io/flowCRMYonetim/gizlilik/` (English: `/privacy/`), which
  the app already links to on the login screen and in the account menu. Use that URL in
  both store listings; override it with `--dart-define=PRIVACY_POLICY_URL=...` if you host
  it elsewhere.
- **Account deletion** — built in: account menu > "Hesabı sil". Point both stores'
  account-deletion questions to it. Deletion removes the account, businesses where the
  user is the only member (with their stored files) and the user's memberships; a sole
  admin of a team must hand over the role first.
- **Data safety / privacy labels** — the app processes: account email, business contact
  names/phone numbers/emails, WhatsApp message content and media, and AI processing of
  messages (OpenAI). No advertising or tracking.
- **Payments** — subscriptions are sold outside the app (roadmap Phase 3); the app has
  no purchase buttons.
- **Demo account for review** — create a reviewer login on the production project with a
  demo business; Apple and Google both ask for one.

## Building a release

```bash
flutter build appbundle --release --dart-define=SUPABASE_URL=https://<project>.supabase.co --dart-define=SUPABASE_ANON_KEY=<anon key> --dart-define=SUPPORT_EMAIL=<support address>
```

```bash
flutter build ipa --release --dart-define=SUPABASE_URL=https://<project>.supabase.co --dart-define=SUPABASE_ANON_KEY=<anon key> --dart-define=SUPPORT_EMAIL=<support address>
```

The anon key is public by design; never pass the service role key to Flutter. Bump
`version:` in `pubspec.yaml` (`1.2.0+12` = name + build number) for every upload.

## Backend before the first release

Deploy every migration and Edge Function, set the secrets from
`supabase/functions/.env.example`, run each `supabase/ops/schedule_*.sql`, configure Auth
SMTP and the recovery email template (see `docs/AUTH_ONBOARDING.md`), and set the Auth
site URL. `delete-account` keeps gateway JWT verification on.

## Still to do before submission

- App icon and launch screen artwork (currently the Flutter defaults).
- Push notifications (needs a Firebase project).
- Store screenshots and descriptions in Turkish.
