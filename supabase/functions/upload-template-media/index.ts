import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function decodeBase64(input: string): Uint8Array {
  const normalized = input.includes(",") ? input.split(",").pop() ?? "" : input;
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

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
  const fileName = body.file_name as string | undefined;
  const mimeType = body.mime_type as string | undefined;
  const fileLengthRaw = body.file_length as number | string | undefined;
  const fileLength = typeof fileLengthRaw === "string"
    ? Number(fileLengthRaw)
    : fileLengthRaw;
  const base64Data = body.base64 as string | undefined;

  if (
    !tenantId ||
    !fileName ||
    !mimeType ||
    !fileLength ||
    Number.isNaN(fileLength) ||
    !base64Data
  ) {
    return new Response(JSON.stringify({ error: "Invalid payload" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const supabaseServiceKey = Deno.env.get("SERVICE_ROLE_KEY") ?? "";
  const whatsappToken = Deno.env.get("WHATSAPP_ACCESS_TOKEN") ?? "";
  const whatsappAppId = Deno.env.get("WHATSAPP_APP_ID") ?? "";
  const whatsappApiVersion = Deno.env.get("WHATSAPP_API_VERSION") ?? "v20.0";
  const whatsappBaseUrl = Deno.env.get("WHATSAPP_BASE_URL") ??
    "https://graph.facebook.com";

  if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceKey) {
    return new Response(JSON.stringify({ error: "Server config missing" }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  if (!whatsappToken || !whatsappAppId) {
    return new Response(JSON.stringify({ error: "WhatsApp config missing" }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
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

  const sessionResponse = await fetch(
    `${whatsappBaseUrl}/${whatsappApiVersion}/${whatsappAppId}/uploads?file_length=${fileLength}&file_type=${encodeURIComponent(mimeType)}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${whatsappToken}`,
      },
    },
  );

  if (!sessionResponse.ok) {
    const errorText = await sessionResponse.text();
    return new Response(JSON.stringify({ error: errorText }), {
      status: 502,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const sessionPayload = await sessionResponse.json();
  const uploadId = sessionPayload?.id as string | undefined;
  if (!uploadId) {
    return new Response(JSON.stringify({ error: "Upload session missing" }), {
      status: 502,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const bytes = decodeBase64(base64Data);
  const uploadResponse = await fetch(
    `${whatsappBaseUrl}/${whatsappApiVersion}/${uploadId}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${whatsappToken}`,
        "file_offset": "0",
        "Content-Type": "application/octet-stream",
      },
      body: bytes,
    },
  );

  if (!uploadResponse.ok) {
    const errorText = await uploadResponse.text();
    return new Response(JSON.stringify({ error: errorText }), {
      status: 502,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const uploadPayload = await uploadResponse.json();
  const handle = uploadPayload?.h ?? uploadPayload?.handle ?? uploadPayload?.id ??
    null;
  if (!handle) {
    return new Response(JSON.stringify({ error: "Handle missing" }), {
      status: 502,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  return new Response(JSON.stringify({
    status: "ok",
    handle,
    upload_id: uploadId,
  }), {
    status: 200,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
});
