import {
  ApiError,
  endpoint,
  jsonResponse,
  readJson,
  uuid,
} from "../_shared/http.ts";
import {
  authenticate,
  requiredEnv,
  requirePermission,
  serviceClient,
} from "../_shared/supabase.ts";
import { templatePage } from "../_shared/template_sync.ts";
import { WhatsAppApi } from "../_shared/whatsapp_api.ts";
import {
  connectionToken,
  resolveConnection,
} from "../_shared/whatsapp_connections.ts";

// One provider page per invocation keeps Edge execution bounded. A repeated page
// is idempotent. The client pins the returned connection across subsequent pages.
Deno.serve(endpoint(async (req) => {
  const { client, userId } = await authenticate(req);
  const body = await readJson(req, 4096);
  const tenantId = uuid(body.tenant_id, "Tenant ID");
  const connectionId = body.connection_id === undefined
    ? null
    : uuid(body.connection_id, "Connection ID");
  const cursor = body.cursor;
  if (
    cursor !== undefined &&
    (typeof cursor !== "string" || !cursor || cursor.length > 2048)
  ) {
    throw new ApiError(400, "invalid_cursor", "Invalid template cursor");
  }
  await requirePermission(client, tenantId, "templates");
  const service = serviceClient();
  const connection = await resolveConnection(service, tenantId, connectionId);
  const api = new WhatsAppApi(
    requiredEnv("WHATSAPP_API_VERSION"),
    await connectionToken(service, connection),
  );
  const payload = await api.data(
    `${connection.waba_id}/message_templates`,
    "GET",
    undefined,
    {
      fields: "id,name,language,category,status,components",
      limit: "100",
      ...(cursor ? { after: cursor as string } : {}),
    },
  );
  const page = templatePage(payload, cursor as string | undefined);
  const { data, error } = await service.rpc("apply_whatsapp_template_page", {
    p_tenant_id: tenantId,
    p_actor_id: userId,
    p_connection_id: connection.id,
    p_templates: page.templates,
  });
  if (error) {
    if (error.code === "42501") {
      throw new ApiError(403, "forbidden", "Template permission required");
    }
    if (error.code === "22023") {
      throw new ApiError(
        409,
        "connection_changed",
        "WhatsApp connection changed; refresh and retry",
      );
    }
    throw new ApiError(
      503,
      "template_sync_unconfirmed",
      "Template sync unavailable; retrying this page is safe",
    );
  }
  return jsonResponse({
    status: "ok",
    updated: data,
    connection_id: connection.id,
    next_cursor: page.cursor,
  });
}));
