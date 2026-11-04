# Authentication and onboarding

Updated 2026-11-05. Sessions, profiles, self-service business creation, in-app
invitations and code-based password recovery are implemented and verified against the
local Supabase stack. Automated invite emails and WhatsApp connection onboarding remain.

## Session lifecycle

`AuthController` subscribes to the Supabase auth event stream and reads the SDK's
current session for local routing. Login publishes that session immediately.
External sign-out, confirmed sign-in and user updates flow through the same path.
Identical user/email snapshots preserve their object identity so routine token
refreshes do not reset tenant-scoped drafts and pagination. Disposed/rebuilt
controllers ignore their former subscriptions and late method completions.

An auth stream error has an explicit handler and re-evaluates the local session.
An expired session is excluded from signed-in routing when evaluated. Server
authorization remains responsible for every protected read/action. This is not a
replacement for JWT verification or RLS. Auth operations have a 20-second UI wait
bound. A request can complete later, and its SDK event still updates local routing.

Signup returning a user without a session stays on the login form and presents
email-confirmation guidance. An obfuscated duplicate-user response does not create
a signed-in app identity. The form preserves password whitespace, supports
autofill/show-hide, owns inline validation and uses bounded scrolling at short
viewport heights. It listens for successful session establishment so delayed
completion can return a pushed login route to the root without a manual refresh.
Raw provider error text is replaced by localized recovery guidance. Membership
fetch failures show retry guidance separately from the empty-membership screen.

## Profile ownership and upgrade

Apply `20261104090000_auth_profiles.sql` after the support workflow migration and
before releasing this client. A security-definer trigger with an empty search path
creates the public profile during Auth user insertion and synchronizes subsequent
Auth email changes. Existing users are backfilled, preserving display names.
The client no longer performs a profile upsert after login/signup. Authenticated
users retain RLS-protected select and own `display_name` update access. Email,
identity, insertion and deletion are server managed.

The profile email is display data. Future invite acceptance must use the verified
Auth identity and must enforce its own tenant/role policy. User-editable metadata
and profile values cannot authorize a membership. The trigger is part of the Auth
transaction, so verify signup and email-change flows in an isolated backend before
deployment. A failed trigger can fail its parent Auth operation.

Configure the Supabase site URL, allowed web/mobile confirmation redirects, email
confirmation, SMTP delivery, password policy and abuse controls during owner setup.
The app retains the configured SDK authentication flow. The test-only mocked client
uses implicit flow to avoid real redirect/storage setup. No production flow or
backend configuration was changed automatically.

## Deferred verification

- `test/auth_session_test.dart` covers session events, identical refresh identity,
  stream errors, expired-session evaluation, signup without a session, immediate
  login, absence of client profile writes, password whitespace, duplicate clicks,
  confirmation UI and navigation back to the root.
- `supabase/tests/auth_profiles.sql` covers profile creation, email sync, name
  preservation and authenticated column restrictions.
- Exercise actual email confirmation, cross-tab logout, token refresh/offline
  recovery, provider revocation, disposed routes and signup errors after deployment
  to an isolated environment. Verify SMTP and redirect configuration there.
- Validate historical profiles and existing member screens after the privilege
  change. Check the complete migrated test suite together with the auth trigger.
- Complete business onboarding, invitation acceptance, recovery UI and tenant
  administration audit before describing onboarding as self-service.

## Business creation and invitations

`20261105090000_tenant_onboarding.sql` moves onboarding into server RPCs:

- `create_business(p_name, p_brand_color)` requires a confirmed email, normalizes the
  name (2-80 characters) and color, creates the tenant with every module, makes the
  caller its admin and records `tenant.created`. A user may create at most three
  businesses until plans exist (`P0010`).
- `create_tenant_invite(p_tenant_id, p_email, p_role, p_permissions)` needs the `users`
  permission. Only admins invite admins (who always get every module); other managers
  can grant only modules they hold. One pending invite per address (re-inviting
  refreshes it), 14-day expiry, at most 50 pending per tenant, existing members
  rejected (`P0011`).
- `my_tenant_invites()` lists pending, unexpired invites for the caller's confirmed
  email; `respond_tenant_invite(p_invite_id, p_accept)` accepts (creating the membership
  atomically, idempotent on retry) or declines. `revoke_tenant_invite(p_invite_id)`.
- Clients can no longer write `tenant_invites` directly; managers keep RLS read access.
  Every transition is written to `tenant_audit_events`.

Invite delivery is in-app: the invitee sees the invite after signing up or signing in
with the invited address, and the admin gets ready-to-share text. Sending invite emails
needs a transactional email provider and is a follow-up. The public join-request flow
still exists for tenants that set `is_public`, below invites and business creation.

## Password recovery

The app uses a one-time code instead of a deep link: `resetPasswordForEmail`, then
`verifyOTP(type: recovery)` and `updateUser(password)`. While the code is being
redeemed, `AuthController` holds back the sign-in event so the reset form stays open
until the new password is saved. The local recovery template
(`supabase/templates/recovery.html`, wired in `supabase/config.toml`) prints
`{{ .Token }}`. On a hosted project, set the same subject and body under
Authentication > Email Templates > Reset Password, and configure SMTP.

Verified locally on 2026-11-05: `supabase/tests/tenant_onboarding.sql` (unconfirmed
users, limits, escalation, cross-user access, idempotent accept, revoke, decline,
expiry) and a live run through Auth/PostgREST: business creation, a 403 on direct
invite insert, invite, accept, then recovery with the code read from the captured
email (wrong code 403, old password rejected, new password accepted).
