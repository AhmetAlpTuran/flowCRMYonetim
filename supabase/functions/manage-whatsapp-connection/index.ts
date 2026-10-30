import { encryptCredential } from "../_shared/credential_cipher.ts";
import {
  ApiError,
  endpoint,
  jsonResponse,
  metaId,
  readJson,
  uuid,
} from "../_shared/http.ts";
import {
  authenticate,
  requireAdmin,
  requiredEnv,
  serviceClient,
} from "../_shared/supabase.ts";
import { verifyConnectionToken, WhatsAppApi } from "../_shared/whatsapp_api.ts";
import { credentialKeys } from "../_shared/whatsapp_connections.ts";

Deno.serve(endpoint(async (req) => {
  const { client, userId } = await authenticate(req);
  const body = await readJson(req, 32768);
  const tenantId = uuid(body.tenant_id, "Tenant ID");
  await requireAdmin(client, tenantId);
  const service = serviceClient();
  if (body.action === "disconnect") {
    const { error } = await service.rpc("disconnect_whatsapp_connection", {
      p_tenant_id: tenantId,
      p_actor_id: userId,
      p_connection_id: uuid(body.connection_id, "Connection ID"),
    });
    if (error) {
      throw new ApiError(
        409,
        "disconnect_failed",
        "Connection could not be disconnected",
      );
    }
    return jsonResponse({ status: "disconnected" });
  }
  if (body.action !== "connect") {
    throw new ApiError(
      400,
      "invalid_action",
      "Connect or disconnect action required",
    );
  }
  const wabaId = metaId(body.waba_id);
  const phoneId = metaId(body.phone_number_id);
  const token = body.access_token;
  if (
    typeof token !== "string" || token.length < 20 || token.length > 16384 ||
    /\s/.test(token)
  ) {
    throw new ApiError(
      400,
      "invalid_token",
      "Valid WhatsApp access token required",
    );
  }
  if (body.is_default !== undefined && typeof body.is_default !== "boolean") {
    throw new ApiError(
      400,
      "invalid_default",
      "Default connection selection must be boolean",
    );
  }
  const { data: existing, error: lookupError } = await service.from(
    "whatsapp_connections",
  )
    .select("id, tenant_id, waba_id").eq("phone_number_id", phoneId)
    .maybeSingle();
  if (lookupError) {
    throw new ApiError(
      503,
      "connection_unavailable",
      "Connection lookup unavailable",
    );
  }
  if (
    existing && (existing.tenant_id !== tenantId || existing.waba_id !== wabaId)
  ) {
    throw new ApiError(
      409,
      "connection_conflict",
      "Phone number cannot be connected to this account",
    );
  }
  const connectionId = existing?.id ?? crypto.randomUUID();
  const keys = credentialKeys();
  const version = requiredEnv("WHATSAPP_API_VERSION");
  const expiresAt = await verifyConnectionToken(
    version,
    token,
    requiredEnv("META_APP_ID"),
    requiredEnv("META_APP_SECRET"),
  );
  const api = new WhatsAppApi(version, token);
  const metadata = await api.findPhone(wabaId, phoneId);
  const encrypted = await encryptCredential(token, {
    tenantId,
    connectionId,
    phoneNumberId: phoneId,
  }, keys);
  // Subscribing the same application to the WABA is repeatable. Disconnecting one
  // number must not unsubscribe the WABA and interrupt its other active numbers.
  const subscribed = await api.data(`${wabaId}/subscribed_apps`, "POST", {});
  if (subscribed.success !== true) {
    throw new ApiError(
      502,
      "subscription_failed",
      "WhatsApp webhook subscription unavailable",
    );
  }
  const { error } = await service.rpc("save_whatsapp_connection", {
    p_tenant_id: tenantId,
    p_actor_id: userId,
    p_connection_id: connectionId,
    p_waba_id: wabaId,
    p_phone_number_id: phoneId,
    p_metadata: { ...metadata, token_expires_at: expiresAt },
    p_credential: encrypted,
    p_is_default: body.is_default ?? false,
  });
  if (error) {
    throw new ApiError(
      409,
      "connection_save_failed",
      "Connection could not be saved; refresh before retrying",
    );
  }
  return jsonResponse({
    status: "connected",
    connection_id: connectionId,
    ...metadata,
    token_expires_at: expiresAt,
  });
}));
