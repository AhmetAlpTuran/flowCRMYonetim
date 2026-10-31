import { decryptCredential, type Keyring } from "./credential_cipher.ts";
import { ApiError } from "./http.ts";
import { type DatabaseClient, requiredEnv } from "./supabase.ts";

export type WhatsAppConnection = {
  id: string;
  tenant_id: string;
  waba_id: string;
  phone_number_id: string;
  status: string;
  is_default: boolean;
  token_expires_at: string | null;
  updated_at: string;
};

export function credentialKeys(): Keyring {
  try {
    const keys = JSON.parse(requiredEnv("WHATSAPP_CREDENTIAL_KEYS"));
    const active = requiredEnv("WHATSAPP_CREDENTIAL_ACTIVE_KEY");
    if (
      !keys || typeof keys !== "object" || Array.isArray(keys) ||
      !/^[A-Za-z0-9_-]{1,40}$/.test(active) || typeof keys[active] !== "string"
    ) throw new Error();
    return { active, keys };
  } catch {
    throw new ApiError(
      503,
      "credential_key_unavailable",
      "WhatsApp credential encryption is not configured",
    );
  }
}

export async function resolveConnection(
  client: DatabaseClient,
  tenantId: string,
  connectionId?: string | null,
): Promise<WhatsAppConnection> {
  let query = client.from("whatsapp_connections")
    .select(
      "id, tenant_id, waba_id, phone_number_id, status, is_default, token_expires_at, updated_at",
    )
    .eq("tenant_id", tenantId).eq("status", "active");
  if (connectionId) query = query.eq("id", connectionId);
  const { data, error } = await query.order("is_default", { ascending: false })
    .order("id").limit(2);
  if (error) {
    throw new ApiError(
      503,
      "connection_unavailable",
      "WhatsApp connection unavailable",
    );
  }
  if (!data?.length) {
    throw new ApiError(
      409,
      "connection_required",
      "Connect a WhatsApp account first",
    );
  }
  if (data.length > 1 && !data[0].is_default) {
    throw new ApiError(
      409,
      "connection_selection_required",
      "Select a WhatsApp connection",
    );
  }
  const connection = data[0] as WhatsAppConnection;
  if (
    connection.token_expires_at &&
    Date.parse(connection.token_expires_at) <= Date.now() + 30000
  ) {
    throw new ApiError(
      409,
      "connection_expired",
      "Reconnect the WhatsApp account",
    );
  }
  return connection;
}

export async function connectionToken(
  client: DatabaseClient,
  connection: WhatsAppConnection,
): Promise<string> {
  const { data, error } = await client.from("whatsapp_connection_credentials")
    .select("key_id, ciphertext, iv").eq("connection_id", connection.id).eq(
      "tenant_id",
      connection.tenant_id,
    ).maybeSingle();
  if (error || !data) {
    throw new ApiError(
      503,
      "connection_credentials_missing",
      "Reconnect the WhatsApp account",
    );
  }
  try {
    return await decryptCredential(data, {
      tenantId: connection.tenant_id,
      connectionId: connection.id,
      phoneNumberId: connection.phone_number_id,
    }, credentialKeys());
  } catch {
    throw new ApiError(
      503,
      "connection_credentials_unavailable",
      "WhatsApp credentials unavailable",
    );
  }
}
