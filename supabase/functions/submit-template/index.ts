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
import { templateSubmission } from "../_shared/template_submission.ts";
import { GraphApiError, WhatsAppApi } from "../_shared/whatsapp_api.ts";
import {
  connectionToken,
  resolveConnection,
} from "../_shared/whatsapp_connections.ts";

// Submits a new template to the tenant's own WhatsApp Business Account (never a
// platform-wide account) and records it through the same idempotent import used
// by sync-templates, so a later sync updates the same row.
Deno.serve(endpoint(async (req) => {
  const { client, userId } = await authenticate(req);
  const body = await readJson(req, 65536);
  const tenantId = uuid(body.tenant_id, "Tenant ID");
  const connectionId = body.connection_id == null
    ? null
    : uuid(body.connection_id, "Connection ID");
  const submission = templateSubmission(body);
  await requirePermission(client, tenantId, "templates");

  const service = serviceClient();
  const connection = await resolveConnection(service, tenantId, connectionId);
  const api = new WhatsAppApi(
    requiredEnv("WHATSAPP_API_VERSION"),
    await connectionToken(service, connection),
  );

  let created: Record<string, unknown>;
  try {
    created = await api.data(
      `${connection.waba_id}/message_templates`,
      "POST",
      submission,
    );
  } catch (error) {
    if (
      error instanceof GraphApiError && error.httpStatus >= 400 &&
      error.httpStatus < 500 && error.providerCode !== 190
    ) {
      throw new ApiError(
        422,
        "template_rejected",
        "WhatsApp rejected the template; check its name, language and content",
      );
    }
    throw error;
  }

  const providerId = created.id;
  const status = typeof created.status === "string" &&
      /^[A-Z_]{1,40}$/.test(created.status)
    ? created.status
    : "PENDING";
  const category = typeof created.category === "string" &&
      /^[A-Z_]{1,40}$/.test(created.category)
    ? created.category
    : submission.category;
  if (typeof providerId !== "string" || !/^[0-9]{1,40}$/.test(providerId)) {
    throw new ApiError(
      502,
      "whatsapp_invalid_response",
      "WhatsApp did not confirm the template; sync templates before retrying",
    );
  }

  const unrecorded = new ApiError(
    503,
    "template_record_unconfirmed",
    "Template was submitted to WhatsApp; sync templates to record it",
  );
  const { error: applyError } = await service.rpc(
    "apply_whatsapp_template_page",
    {
      p_tenant_id: tenantId,
      p_actor_id: userId,
      p_connection_id: connection.id,
      p_templates: [{
        id: providerId,
        name: submission.name,
        language: submission.language,
        status,
        category,
        components: submission.components,
      }],
    },
  );
  if (applyError) throw unrecorded;
  const { data: row, error: rowError } = await service.from("templates")
    .select("id")
    .eq("tenant_id", tenantId)
    .eq("waba_id", connection.waba_id)
    .eq("name", submission.name)
    .eq("language", submission.language)
    .maybeSingle();
  if (rowError || !row) throw unrecorded;

  return jsonResponse({
    status: "ok",
    template_id: row.id,
    whatsapp_status: status,
    wa_template_id: providerId,
    connection_id: connection.id,
  });
}));
