# API reference register

Reviewed 2026-10-30. Record contract decisions here as integrations are implemented.

- Supabase database functions: https://supabase.com/docs/guides/database/functions
  Use invoker rights by default, fixed search paths, explicit execute grants.
- Supabase RLS: https://supabase.com/docs/guides/database/postgres/row-level-security
  Client filtering is not authorization; privileged functions need explicit checks.
- Meta maintained WhatsApp collection, template send example:
  https://www.postman.com/meta/whatsapp-business-platform/request/lwtlz1k/send-message-template-interactive
  Send-time components contain parameters, not creation-time text/format/example fields.

Before provider integration, read the current detailed official endpoint documentation.
The bundled WPAPI collection is historical supporting material, not the version authority.
Graph version must be explicit configuration and verified during deployment.

## Template parameter follow-up (2026-10-30)

- Meta-maintained media example: https://www.postman.com/meta/whatsapp-business-platform/request/2qbotrb/send-message-template-media
- Meta parameter/component reference linked from its collection:
  https://developers.facebook.com/docs/whatsapp/cloud-api/reference/messages
- Local `wpapi/WhatsApp Cloud API.postman_collection.json` contains text/media request
  bodies consistent with the send-time parameters structure. It is supporting
  historical evidence, not proof of current version support.

The current Meta Postman pages were reachable; direct Meta reference requests
returned HTTP 429 during this pass. Named-parameter support is implemented with
`parameter_name`, but live provider conformance, supported limits and current Graph
version must be rechecked before release. No integration success is claimed.

## Queue/background processing (2026-10-30)

- PostgreSQL locking/queue consumers: https://www.postgresql.org/docs/current/sql-select.html
  `FOR UPDATE SKIP LOCKED` is appropriate for claiming queue rows across consumers;
  do not use it as a consistent audience snapshot. Enqueue uses a normal atomic
  insert-select and a campaign row lock instead.
- Supabase scheduling: https://supabase.com/docs/guides/functions/schedule-functions
  and https://supabase.com/docs/guides/cron
  Scheduled invocation and secret storage must be configured during backend setup.
  Cron integration is not active in this checkout yet.
- Static parser: https://pypi.org/project/pglast/ (8.7 used from a temporary tools
  directory; not added to app dependencies). Grammar parsing does not execute SQL.

## WhatsApp connection foundation (2026-10-30)

- Meta phone account relationship:
  https://www.postman.com/meta/whatsapp-business-platform/folder/ypba0gk/phone-numbers
- Meta token debugging reference:
  https://developers.facebook.com/docs/facebook-login/guides/access-tokens/debugging-and-error-handling/
  Direct retrieval was unavailable during this pass; the bundled Meta Embedded
  Signup collection supplies the debug_token request/response structure. Live
  permission and token-type conformance remains a release verification item.
- Supabase official package registry metadata:
  https://registry.npmjs.org/@supabase/supabase-js/latest
  Resolved 2.118.0; new shared imports pin that release instead of floating @2.

## Worker and account-scoped template sync (2026-10-31)

- Meta-maintained template listing endpoint:
  https://www.postman.com/meta/whatsapp-business-platform/request/qtgr0i7/get-all-templates-default-fields
  GET `/{waba-id}/message_templates`. The page remains labeled MOVED; bundled official
  collection examples supplement its response structure. Provider pagination hosts
  are never followed: only cursors are passed back to the fixed Graph endpoint.
- Meta error-code references were requested but returned HTTP 429:
  https://developers.facebook.com/documentation/business-messaging/whatsapp/support/error-codes
  https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/
  Retry classification is deliberately conservative. Live conformance for error
  codes, `biz_opaque_callback_data`, template fields and supported versions remains
  pending; no successful provider integration is claimed.
- The previously reviewed Supabase cron/pg_net/Vault guidance informs the optional
  worker scheduling script. It has been authored, not installed or executed.

## Campaign client state (2026-10-31)

- Riverpod provider families and disposal:
  https://riverpod.dev/docs/concepts2/family
  https://riverpod.dev/docs/concepts2/auto_dispose
  Current docs describe Riverpod 3; this existing app remains on Riverpod 2.x.
  Family/auto-dispose concepts apply, but implementation uses the installed 2.x
  StateNotifier/FutureProvider APIs and static analysis rather than copying 3.x code.

## Webhook authenticity and receipts (2026-10-31)

- Meta's archived SDK documents exact-body app-secret signature verification and
  subscription challenge handling:
  https://whatsapp.github.io/WhatsApp-Nodejs-SDK/api-reference/webhooks/start/
  It is primary historical evidence, not proof of current API version support.
- Current Graph webhook validation and WhatsApp payload references were requested:
  https://developers.facebook.com/docs/graph-api/webhooks/getting-started#validate-payloads
  https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/components
  The first returned 429 and the second was inaccessible. Current payload limits,
  business-scoped identity support and callback metadata require release verification.
- Meta's maintained message collection documents status tracking by message ID:
  https://www.postman.com/meta/whatsapp-business-platform/folder/o48mro7/messages
