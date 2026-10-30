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
