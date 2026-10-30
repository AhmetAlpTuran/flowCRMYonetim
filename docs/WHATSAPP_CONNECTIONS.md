# Tenant WhatsApp connections

Implemented foundation: metadata/credential tables, administration endpoint, token
verification, encrypted storage and a reusable tenant-scoped resolver. Campaign,
inbox, bot and template senders must be migrated to this resolver before release.
Embedded Signup UI/code exchange and signed webhook ingestion are still pending.
Do not expose the existing unsigned bot webhook as a production receiver.

## Ownership and credentials

Each phone-number ID maps to exactly one tenant and WABA. Connection identity is
immutable; reconnecting rotates credentials for the same identity. Multiple numbers
may belong to one tenant; an optional default connection removes ambiguity. A
resolver never falls back to global WhatsApp credentials or another tenant's data.

`whatsapp_connections` contains readable metadata protected by tenant RLS.
`whatsapp_connection_credentials` contains only AES-256-GCM ciphertext, a fresh
96-bit IV and a key ID. It has no user privileges/policies or credential-reading
definer function. Authenticated encryption binds tenant ID, connection ID and phone
ID, so copying ciphertext to a different connection fails decryption.

`manage-whatsapp-connection` accepts authenticated POST requests. Only tenant
administrators can connect/disconnect; SQL mutation RPCs recheck the actor role.
The existing users permission no longer grants direct membership writes that could
promote a delegated user into an administrator. Delegated team-management workflows
will be implemented with explicit role restrictions in the tenancy milestone.

The connect action verifies the token belongs to this Meta app, includes management
and messaging scopes, and has not expired. It verifies WABA/phone membership against
Meta, subscribes the app to the WABA and atomically stores metadata plus ciphertext.
No plaintext token is returned, included in audit details or logged. The request
body is size-limited, Graph hosts/paths are constrained, redirects are refused, and
provider pagination follows only cursor values. API errors use sanitized codes.

Disconnect disables this local connection and deletes its stored credential. It
does not revoke the provider token or unsubscribe the entire WABA, which may serve
other connected numbers. Metadata remains available for historical references.

## Required server configuration

- Existing Supabase URL, anon key and server-only `SERVICE_ROLE_KEY`.
- `META_APP_ID` and `META_APP_SECRET` for this SaaS's Meta app.
- Explicit `WHATSAPP_API_VERSION`, chosen from currently supported Meta versions
  during deployment. There is no version fallback in the new integration.
- `WHATSAPP_CREDENTIAL_KEYS`: a JSON object mapping key IDs to base64-encoded random
  32-byte keys, for example `{"primary-v1":"<base64 key>"}`.
- `WHATSAPP_CREDENTIAL_ACTIVE_KEY`: the key ID used for new encryption.

Generate keys with a cryptographically secure generator and store them in backend
secrets, separately from database backups and source control. Never put them in
Flutter configuration. Keep old keys while any credential still references them;
switching the active key does not automatically re-encrypt existing records.
Rotation/re-encryption operations belong in the operations milestone.

The token inspection endpoint requires its input token in a Graph query parameter.
Do not enable URL/header/body logging for provider requests. This application logs
only sanitized failure codes and generated request IDs. Configure monitoring with
equivalent redaction during deployment.

Local Edge configuration now targets Deno 2. The new shared Supabase client is
pinned to `@supabase/supabase-js@2.118.0`; existing endpoints will be migrated to it
incrementally. Deno 2.9.6 was obtained through the temporary npm tool runner for
static checks; no Deno test suites were executed.

## Deferred checks

- `credential_cipher_test.ts`: independent IVs, authenticated context, tampering,
  key rotation and missing/invalid keys.
- `whatsapp_api_test.ts`: app/scope/expiry validation, phone membership, constrained
  pagination, redacted errors, bounded JSON input and UUID normalization.
- `supabase/tests/whatsapp_connections.sql`: tenant reads, private credentials,
  immutable identity, phone uniqueness, cross-tenant campaign references, actor
  permissions, privilege-escalation prevention and local disconnect.

These are authored but unrun. Live token verification, WABA subscription, number
registration/availability, key recovery and end-to-end onboarding require the later
verification phase. Connection status active means credentials/account association
were verified; it is not proof that a message was delivered or billing is ready.
