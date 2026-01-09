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

  const replyText = `Mock yanit: ${text}`;

  await supabase.from("messages").insert({
    tenant_id: tenantId,
    conversation_id: conversationId,
    sender: "WhatsApp (Mock)",
    body: replyText,
    is_from_customer: true,
    sent_at: now,
  });

  await supabase
    .from("conversations")
    .update({ last_message: replyText, updated_at: now })
    .eq("id", conversationId);

  return new Response(JSON.stringify({ status: "ok", reply: replyText }), {
    status: 200,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
});
