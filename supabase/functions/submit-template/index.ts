import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const body = await req.json().catch(() => ({}));
  const tenantId = body.tenant_id as string | undefined;
  const name = body.name as string | undefined;
  const category = body.category as string | undefined;
  const language = body.language as string | undefined;
  const components = body.components ?? {};

  if (!tenantId || !name || !category || !language) {
    return new Response(JSON.stringify({ error: "Invalid payload" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const supabaseServiceKey = Deno.env.get("SERVICE_ROLE_KEY") ?? "";
  const whatsappToken = Deno.env.get("WHATSAPP_ACCESS_TOKEN") ?? "";
  const whatsappWabaId = Deno.env.get("WHATSAPP_WABA_ID") ?? "";
  const whatsappApiVersion = Deno.env.get("WHATSAPP_API_VERSION") ?? "v20.0";
  const whatsappBaseUrl = Deno.env.get("WHATSAPP_BASE_URL") ??
    "https://graph.facebook.com";
  if (!whatsappToken || !whatsappWabaId) {
    return new Response(JSON.stringify({ error: "WhatsApp config missing" }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const supabaseService = createClient(supabaseUrl, supabaseServiceKey, {
    auth: { persistSession: false },
  });

  const { data: userData } = await supabaseUser.auth.getUser();
  const user = userData.user;
  if (!user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const { data: membership } = await supabaseUser
    .from("tenant_memberships")
    .select("role, permissions")
    .eq("tenant_id", tenantId)
    .eq("user_id", user.id)
    .maybeSingle();

  const permissions = (membership?.permissions ?? []) as string[];
  const hasAccess =
    membership &&
    (membership.role === "admin" || permissions.includes("templates"));
  if (!hasAccess) {
    return new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const createResponse = await fetch(
    `${whatsappBaseUrl}/${whatsappApiVersion}/${whatsappWabaId}/message_templates`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${whatsappToken}`,
      },
      body: JSON.stringify({
        name,
        language,
        category,
        components,
      }),
    },
  );

  if (!createResponse.ok) {
    const errorText = await createResponse.text();
    return new Response(JSON.stringify({ error: errorText }), {
      status: 502,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const createPayload = await createResponse.json();
  const apiStatus = createPayload?.status ?? "Beklemede";

  const { data, error } = await supabaseService
    .from("templates")
    .insert({
      tenant_id: tenantId,
      name,
      category,
      language,
      status: apiStatus,
      components,
    })
    .select("id")
    .single();

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  return new Response(JSON.stringify({
    status: "ok",
    template_id: data.id,
    whatsapp_status: apiStatus,
  }), {
    status: 200,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
});
