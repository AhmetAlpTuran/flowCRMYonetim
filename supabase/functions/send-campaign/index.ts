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
  const campaignId = body.campaign_id as string | undefined;
  if (!campaignId) {
    return new Response(JSON.stringify({ error: "campaign_id required" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const supabaseServiceKey = Deno.env.get("SERVICE_ROLE_KEY") ?? "";

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

  const { data: campaign, error: campaignError } = await supabaseUser
    .from("campaigns")
    .select("id, tenant_id, audience_filter, template_id")
    .eq("id", campaignId)
    .maybeSingle();

  if (campaignError || !campaign) {
    return new Response(JSON.stringify({ error: "Campaign not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const { data: membership } = await supabaseService
    .from("tenant_memberships")
    .select("role, permissions")
    .eq("tenant_id", campaign.tenant_id)
    .eq("user_id", user.id)
    .maybeSingle();

  const permissions = (membership?.permissions ?? []) as string[];
  const hasAccess =
    membership &&
    (membership.role === "admin" || permissions.includes("campaigns"));
  if (!hasAccess) {
    return new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const filter = (campaign.audience_filter ?? {}) as Record<string, unknown>;
  let contactsQuery = supabaseService
    .from("contacts")
    .select("id, tags, last_contacted_at")
    .eq("tenant_id", campaign.tenant_id);

  if (typeof filter.segment === "string") {
    contactsQuery = contactsQuery.contains("tags", [filter.segment]);
  }

  if (typeof filter.last_contacted === "string") {
    const match = /^(\d+)(d)$/.exec(filter.last_contacted);
    if (match) {
      const days = Number(match[1]);
      const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
      contactsQuery = contactsQuery.gte("last_contacted_at", cutoff.toISOString());
    }
  }

  const { data: contacts } = await contactsQuery.limit(100);
  const jobs = (contacts ?? []).map((contact) => ({
    tenant_id: campaign.tenant_id,
    campaign_id: campaign.id,
    contact_id: contact.id,
    template_id: campaign.template_id,
    status: "sent",
    attempts: 1,
  }));

  if (jobs.length > 0) {
    await supabaseService.from("message_jobs").insert(jobs);
  }

  await supabaseService
    .from("campaigns")
    .update({ status: "completed" })
    .eq("id", campaign.id);

  return new Response(
    JSON.stringify({
      status: "ok",
      sent: jobs.length,
      failed: 0,
    }),
    {
      status: 200,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    },
  );
});
