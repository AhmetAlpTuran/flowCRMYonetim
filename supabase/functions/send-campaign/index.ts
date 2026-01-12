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

  const { data: template } = await supabaseService
    .from("templates")
    .select("name, language, components")
    .eq("id", campaign.template_id)
    .maybeSingle();

  if (!template) {
    return new Response(JSON.stringify({ error: "Template not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const filter = (campaign.audience_filter ?? {}) as Record<string, unknown>;
  const templateComponents = Array.isArray(template.components)
    ? template.components
    : (template.components?.components ?? []);
  let contactsQuery = supabaseService
    .from("consented_contacts")
    .select("id, tags, last_contacted_at, phone")
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
  const jobs = [];
  let sent = 0;
  let failed = 0;

  for (const contact of contacts ?? []) {
    const to = String(contact.phone ?? "").replace(/\D/g, "");
    if (!to) {
      failed += 1;
      jobs.push({
        tenant_id: campaign.tenant_id,
        campaign_id: campaign.id,
        consented_contact_id: contact.id,
        template_id: campaign.template_id,
        status: "failed",
        attempts: 1,
        last_error: "Contact phone missing",
      });
      continue;
    }

    const response = await fetch(
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
          to,
          type: "template",
          template: {
            name: template.name,
            language: { code: template.language },
            components: templateComponents,
          },
        }),
      },
    );

    if (!response.ok) {
      const errorText = await response.text();
      failed += 1;
    jobs.push({
      tenant_id: campaign.tenant_id,
      campaign_id: campaign.id,
      consented_contact_id: contact.id,
      template_id: campaign.template_id,
      status: "failed",
      attempts: 1,
      last_error: errorText,
    });
      continue;
    }

    sent += 1;
    jobs.push({
      tenant_id: campaign.tenant_id,
      campaign_id: campaign.id,
      consented_contact_id: contact.id,
      template_id: campaign.template_id,
      status: "sent",
      attempts: 1,
    });

    await supabaseService
      .from("consented_contacts")
      .update({ last_contacted_at: new Date().toISOString() })
      .eq("id", contact.id);
  }

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
      sent,
      failed,
    }),
    {
      status: 200,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    },
  );
});
