import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  TemplateInputError,
  templateInputs,
} from "../_shared/template_parameters.ts";

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
const reply = (status: number, value: unknown) =>
  new Response(JSON.stringify(value), { status, headers });

// The form uses this manifest; placeholder parsing stays in one server module.
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });
  const authorization = req.headers.get("Authorization");
  if (!authorization) return reply(401, { error: "Unauthorized" });
  try {
    const body = await req.json().catch(() => null);
    const uuid =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (
      !body ||
      typeof body.tenant_id !== "string" ||
      typeof body.template_id !== "string" ||
      !uuid.test(body.tenant_id) ||
      !uuid.test(body.template_id)
    ) {
      return reply(400, { error: "Tenant and template IDs required" });
    }
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceKey)
      return reply(503, { error: "Server config missing" });
    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });
    const { data: identity, error: authError } =
      await userClient.auth.getUser();
    if (authError || !identity.user)
      return reply(401, { error: "Unauthorized" });
    const { data: allowed, error: permissionError } = await userClient.rpc(
      "user_has_permission",
      {
        target_tenant: body.tenant_id,
        permission: "campaigns",
      },
    );
    if (permissionError || allowed !== true)
      return reply(403, { error: "Forbidden" });
    const service = createClient(url, serviceKey, {
      auth: { persistSession: false },
    });
    const { data: template, error } = await service
      .from("templates")
      .select("components, status")
      .eq("tenant_id", body.tenant_id)
      .eq("id", body.template_id)
      .maybeSingle();
    if (error) return reply(503, { error: "Template unavailable" });
    if (!template) return reply(404, { error: "Template not found" });
    if (String(template.status).toUpperCase() !== "APPROVED") {
      return reply(409, { error: "Template must be approved before sending" });
    }
    return reply(200, { inputs: templateInputs(template.components) });
  } catch (error) {
    if (error instanceof TemplateInputError)
      return reply(422, { error: error.message });
    return reply(500, { error: "Template inputs unavailable" });
  }
});
