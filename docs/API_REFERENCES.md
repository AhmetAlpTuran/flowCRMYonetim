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
