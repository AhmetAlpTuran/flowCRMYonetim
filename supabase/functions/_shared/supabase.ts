import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { ApiError } from "./http.ts";

export type DatabaseClient = SupabaseClient;

export function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) {
    throw new ApiError(
      503,
      "server_configuration",
      "Server configuration incomplete",
    );
  }
  return value;
}

export function serviceClient(): DatabaseClient {
  return createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SERVICE_ROLE_KEY"),
    {
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );
}

export async function authenticate(req: Request) {
  const authorization = req.headers.get("Authorization");
  if (!authorization?.match(/^Bearer \S+$/i)) {
    throw new ApiError(401, "unauthorized", "Sign in required");
  }
  const client = createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_ANON_KEY"),
    {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) {
    throw new ApiError(401, "unauthorized", "Sign in required");
  }
  return { userId: data.user.id, client };
}

export async function requirePermission(
  client: DatabaseClient,
  tenantId: string,
  permission: string,
) {
  const { data, error } = await client.rpc("user_has_permission", {
    target_tenant: tenantId,
    permission,
  });
  if (error || data !== true) {
    throw new ApiError(403, "forbidden", "Permission required");
  }
}

export async function requireAdmin(client: DatabaseClient, tenantId: string) {
  const { data, error } = await client.rpc("is_tenant_admin", {
    target_tenant: tenantId,
  });
  if (error || data !== true) {
    throw new ApiError(403, "admin_required", "Tenant administrator required");
  }
}
