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
  const conversationId = body.conversation_id as string | undefined;
  const text = body.body as string | undefined;
  const sender = (body.sender as string | undefined) ?? "Temsilci";

  if (!tenantId || !conversationId || !text) {
    return new Response(JSON.stringify({ error: "Invalid payload" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const whatsappToken = Deno.env.get("WHATSAPP_ACCESS_TOKEN") ?? "";
  const whatsappPhoneNumberId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID") ?? "";
  const whatsappApiVersion = Deno.env.get("WHATSAPP_API_VERSION") ?? "v20.0";
  const whatsappBaseUrl = Deno.env.get("WHATSAPP_BASE_URL") ??
    "https://graph.facebook.com";
  if (!whatsappToken || !whatsappPhoneNumberId) {
    return new Response(JSON.stringify({ error: "WhatsApp config missing" }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData } = await supabase.auth.getUser();
  const user = userData.user;
  if (!user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const { data: membership } = await supabase
    .from("tenant_memberships")
    .select("role, permissions")
    .eq("tenant_id", tenantId)
    .eq("user_id", user.id)
    .maybeSingle();

  const permissions = (membership?.permissions ?? []) as string[];
  const hasAccess =
    membership && (membership.role === "admin" || permissions.includes("inbox"));
  if (!hasAccess) {
    return new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const { data: conversation } = await supabase
    .from("conversations")
    .select("id, contact_id")
    .eq("id", conversationId)
    .maybeSingle();

  if (!conversation?.contact_id) {
    return new Response(JSON.stringify({ error: "Contact not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const { data: contact } = await supabase
    .from("contacts")
    .select("phone")
    .eq("id", conversation.contact_id)
    .maybeSingle();

  if (!contact?.phone) {
    return new Response(JSON.stringify({ error: "Contact phone missing" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const sendResponse = await fetch(
    `${whatsappBaseUrl}/${whatsappApiVersion}/${whatsappPhoneNumberId}/messages`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${whatsappToken}`,
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        recipient_type: "individual",
        to: String(contact.phone).replace(/\D/g, ""),
        type: "text",
        text: {
          body: text,
        },
      }),
    },
  );

  if (!sendResponse.ok) {
    const errorText = await sendResponse.text();
    return new Response(JSON.stringify({ error: errorText }), {
      status: 502,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const sendPayload = await sendResponse.json();
  const waMessageId = sendPayload?.messages?.[0]?.id ?? null;
  const now = new Date().toISOString();

  const { error: insertError } = await supabase.from("messages").insert({
    tenant_id: tenantId,
    conversation_id: conversationId,
    sender,
    body: text,
    is_from_customer: false,
    sent_at: now,
  });

  if (insertError) {
    return new Response(JSON.stringify({ error: insertError.message }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  await supabase
    .from("conversations")
    .update({ last_message: text, updated_at: now })
    .eq("id", conversationId);

  return new Response(JSON.stringify({ status: "ok", wa_message_id: waMessageId }), {
    status: 200,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
});
