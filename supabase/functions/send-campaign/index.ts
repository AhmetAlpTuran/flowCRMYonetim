import {
  ApiError,
  endpoint,
  jsonResponse,
  readJson,
  uuid,
} from "../_shared/http.ts";
import {
  authenticate,
  requirePermission,
  serviceClient,
} from "../_shared/supabase.ts";
import {
  TemplateInputError,
  templateInputs,
  validateTemplateBindings,
} from "../_shared/template_parameters.ts";
import {
  connectionToken,
  resolveConnection,
} from "../_shared/whatsapp_connections.ts";

// User requests only enqueue. External sends belong exclusively to campaign-worker.
Deno.serve(endpoint(async (req) => {
  const { client, userId } = await authenticate(req);
  const body = await readJson(req, 4096);
  const campaignId = uuid(body.campaign_id, "Campaign ID");
  const { data: campaign, error: campaignError } = await client.from(
    "campaigns",
  )
    .select(
      "id, tenant_id, audience_filter, template_id, template_bindings, connection_id, queued_at, revision",
    )
    .eq("id", campaignId).maybeSingle();
  if (campaignError) {
    throw new ApiError(503, "campaign_unavailable", "Campaign unavailable");
  }
  if (!campaign) {
    throw new ApiError(404, "campaign_not_found", "Campaign not found");
  }
  await requirePermission(client, campaign.tenant_id, "campaigns");

  async function progress() {
    const { data, error } = await client.rpc("campaign_progress", {
      p_campaign_id: campaignId,
    });
    if (error) {
      throw new ApiError(
        503,
        "progress_unavailable",
        "Campaign progress unavailable; refresh this campaign before retrying",
      );
    }
    return data;
  }
  if (campaign.queued_at) {
    return jsonResponse({
      status: "already_queued",
      campaign_id: campaignId,
      progress: await progress(),
    });
  }
  if (
    !Number.isSafeInteger(body.expected_revision) ||
    (body.expected_revision as number) < 0
  ) {
    throw new ApiError(
      400,
      "revision_required",
      "Review and save the campaign before starting it",
    );
  }
  if (campaign.revision !== body.expected_revision) {
    throw new ApiError(
      409,
      "campaign_changed",
      "Campaign changed; reopen and review the current draft",
    );
  }
  const service = serviceClient();
  const connection = await resolveConnection(
    service,
    campaign.tenant_id,
    campaign.connection_id,
  );
  await connectionToken(service, connection); // Verify decryptability before queueing.
  const { data: template, error: templateError } = await service.from(
    "templates",
  )
    .select("name, language, components, status, waba_id").eq(
      "id",
      campaign.template_id,
    )
    .eq("tenant_id", campaign.tenant_id).maybeSingle();
  if (templateError) {
    throw new ApiError(503, "template_unavailable", "Template unavailable");
  }
  if (!template || String(template.status).toUpperCase() !== "APPROVED") {
    throw new ApiError(
      409,
      "template_not_approved",
      "Select an approved template",
    );
  }
  if (template.waba_id !== connection.waba_id) {
    throw new ApiError(
      409,
      "template_account_mismatch",
      "Sync and select a template from this WhatsApp account",
    );
  }
  try {
    validateTemplateBindings(
      templateInputs(template.components),
      campaign.template_bindings,
    );
  } catch (error) {
    throw new ApiError(
      422,
      "invalid_template_values",
      error instanceof TemplateInputError
        ? error.message
        : "Invalid template values",
    );
  }
  const expected = {
    audience_filter: campaign.audience_filter,
    template_id: campaign.template_id,
    template_bindings: campaign.template_bindings,
    connection_id: connection.id,
    connection: {
      id: connection.id,
      waba_id: connection.waba_id,
      phone_number_id: connection.phone_number_id,
    },
    template: {
      name: template.name,
      language: template.language,
      components: template.components,
    },
  };
  const { error } = await service.rpc("enqueue_campaign", {
    p_campaign_id: campaignId,
    p_actor_id: userId,
    p_expected: expected,
  });
  if (error) {
    if (error.code === "42501") {
      throw new ApiError(403, "forbidden", "Campaign permission required");
    }
    if (error.code === "40001") {
      throw new ApiError(
        409,
        "campaign_changed",
        "Campaign changed; review it again",
      );
    }
    if (error.code === "55000") {
      throw new ApiError(
        409,
        "campaign_previously_attempted",
        "This campaign was already attempted; review its history",
      );
    }
    if (error.code === "22023") {
      throw new ApiError(
        422,
        "campaign_not_ready",
        "Check the audience, approved template and WhatsApp connection",
      );
    }
    throw new ApiError(
      503,
      "enqueue_unconfirmed",
      "Queue result unavailable; refresh this campaign before retrying",
    );
  }
  return jsonResponse({
    status: "queued",
    campaign_id: campaignId,
    progress: await progress(),
  }, 202);
}));
