import { endpoint, jsonResponse, readJson, uuid } from "../_shared/http.ts";
import {
  authenticate,
  requiredEnv,
  requirePermission,
  serviceClient,
} from "../_shared/supabase.ts";
import {
  maxTemplateMediaBytes,
  templateMedia,
} from "../_shared/template_submission.ts";
import { WhatsAppApi } from "../_shared/whatsapp_api.ts";
import {
  connectionToken,
  resolveConnection,
} from "../_shared/whatsapp_connections.ts";

// Uploads a template header sample with the tenant's own connection token and
// returns Meta's header handle. Nothing is stored server side.
Deno.serve(endpoint(async (req) => {
  const { client } = await authenticate(req);
  // Base64 inflates content by 4/3; allow headroom for the JSON envelope.
  const body = await readJson(
    req,
    Math.ceil(maxTemplateMediaBytes() * 4 / 3) + 4096,
  );
  const tenantId = uuid(body.tenant_id, "Tenant ID");
  const connectionId = body.connection_id == null
    ? null
    : uuid(body.connection_id, "Connection ID");
  const media = templateMedia(body);
  await requirePermission(client, tenantId, "templates");

  const service = serviceClient();
  const connection = await resolveConnection(service, tenantId, connectionId);
  const api = new WhatsAppApi(
    requiredEnv("WHATSAPP_API_VERSION"),
    await connectionToken(service, connection),
  );
  const handle = await api.uploadTemplateMedia(
    requiredEnv("META_APP_ID"),
    media,
  );
  return jsonResponse({
    status: "ok",
    handle,
    connection_id: connection.id,
  });
}));
