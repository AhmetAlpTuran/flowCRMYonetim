import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-api-key",
};

const defaultPrompt =
  "Kisa, profesyonel bir musteri temsilcisi gibi yanit ver.";

const maxKnowledgeLength = 600;
const defaultMemoryHours = 6;
const defaultHistoryMessages = 12;

function normalizePhone(value: string): string {
  return value.replace(/\D/g, "");
}

function buildKnowledgeContext(
  entries: Array<{ title?: string; content?: string }>,
): string {
  if (entries.length == 0) {
    return "";
  }
  const lines = entries.map((entry) => {
    const title = (entry.title ?? "Not").trim();
    const content = (entry.content ?? "").trim();
    const trimmed = content.length > maxKnowledgeLength
      ? `${content.slice(0, maxKnowledgeLength)}...`
      : content;
    return `- ${title}: ${trimmed}`;
  });
  return lines.join("\n");
}

function parseWebhookTimestamp(value?: string): string | null {
  if (!value) {
    return null;
  }
  const seconds = Number(value);
  if (Number.isNaN(seconds)) {
    return null;
  }
  return new Date(seconds * 1000).toISOString();
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const verifyToken = Deno.env.get("WHATSAPP_WEBHOOK_TOKEN") ?? "";

  if (req.method === "GET") {
    const url = new URL(req.url);
    const mode = url.searchParams.get("hub.mode");
    const token = url.searchParams.get("hub.verify_token");
    const challenge = url.searchParams.get("hub.challenge");
    if (mode === "subscribe" && token && token === verifyToken && challenge) {
      return new Response(challenge, { status: 200, headers: corsHeaders });
    }
    return new Response("Forbidden", { status: 403, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const body = await req.json().catch(() => ({}));
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseServiceKey = Deno.env.get("SERVICE_ROLE_KEY") ?? "";
  const whatsappToken = Deno.env.get("WHATSAPP_ACCESS_TOKEN") ?? "";
  const whatsappPhoneNumberId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID") ?? "";
  const whatsappApiVersion = Deno.env.get("WHATSAPP_API_VERSION") ?? "v20.0";
  const whatsappBaseUrl = Deno.env.get("WHATSAPP_BASE_URL") ??
    "https://graph.facebook.com";
  if (!supabaseUrl || !supabaseServiceKey) {
    return new Response(JSON.stringify({ error: "Server config missing" }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
  if (!whatsappToken) {
    return new Response(JSON.stringify({ error: "WhatsApp config missing" }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const supabase = createClient(supabaseUrl, supabaseServiceKey, {
    auth: { persistSession: false },
  });

  const entry = Array.isArray(body.entry) ? body.entry[0] : null;
  const change = entry?.changes?.[0];
  const value = change?.value ?? {};
  const statuses = Array.isArray(value?.statuses) ? value.statuses : [];
  if (statuses.length > 0) {
    for (const status of statuses) {
      const messageId = status?.id as string | undefined;
      if (!messageId) {
        continue;
      }
      const state = status?.status as string | undefined;
      const timestamp = parseWebhookTimestamp(status?.timestamp as string | undefined);
      const updates: Record<string, string> = {};
      if (state) {
        updates.wa_status = state;
      }
      if (timestamp && state == "delivered") {
        updates.delivered_at = timestamp;
      }
      if (timestamp && state == "read") {
        updates.read_at = timestamp;
      }
      if (Object.keys(updates).length > 0) {
        await supabase
          .from("messages")
          .update(updates)
          .eq("wa_message_id", messageId);
      }
    }
    return new Response(JSON.stringify({ status: "ok" }), {
      status: 200,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  let tenantId = (body.tenant_id ?? body.tenantId) as string | undefined;
  let phoneNumberId = (body.phone_number_id ?? body.phoneNumberId) as string | undefined;
  let messageText = (body.message ?? body.text ?? body.body) as string | undefined;
  let phone = (body.phone ?? body.from) as string | undefined;
  let contactName = (body.contact_name ?? body.contactName ?? body.name ?? phone)
    as string | undefined;

  if (!messageText && entry) {
    const message = Array.isArray(value.messages) ? value.messages[0] : null;
    if (!message) {
      return new Response(JSON.stringify({ status: "ignored" }), {
        status: 200,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }
    phone = message.from ?? phone;
    phoneNumberId = value?.metadata?.phone_number_id ?? phoneNumberId;
    contactName = value?.contacts?.[0]?.profile?.name ?? contactName ?? phone;
    messageText = message?.text?.body ??
      message?.image?.caption ??
      message?.video?.caption ??
      message?.document?.caption ??
      `[${message.type ?? "mesaj"}]`;
  }

  if (!tenantId) {
    tenantId = Deno.env.get("DEFAULT_TENANT_ID") ??
      "11111111-1111-1111-1111-111111111111";
  }

  if (!tenantId || !messageText || !phone) {
    return new Response(JSON.stringify({ error: "Invalid payload" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const activePhoneNumberId = phoneNumberId ?? whatsappPhoneNumberId;

  const now = new Date().toISOString();

  let { data: contact } = await supabase
    .from("contacts")
    .select("id, full_name")
    .eq("tenant_id", tenantId)
    .eq("phone", phone)
    .maybeSingle();

  if (!contact) {
    const { data: inserted } = await supabase
      .from("contacts")
      .insert({
        tenant_id: tenantId,
        full_name: contactName ?? phone,
        phone,
        tags: [],
      })
      .select("id, full_name")
      .single();
    contact = inserted ?? null;
  } else if (contactName && contact.full_name != contactName) {
    await supabase
      .from("contacts")
      .update({ full_name: contactName })
      .eq("id", contact.id);
  }

  if (!contact) {
    return new Response(JSON.stringify({ error: "Contact not found" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  let { data: conversation } = await supabase
    .from("conversations")
    .select("id, title, unread_count")
    .eq("tenant_id", tenantId)
    .eq("contact_id", contact.id)
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!conversation) {
    const { data: created } = await supabase
      .from("conversations")
      .insert({
        tenant_id: tenantId,
        contact_id: contact.id,
        title: contactName ?? phone,
        last_message: messageText,
        status: "open",
        tags: [],
        unread_count: 1,
        updated_at: now,
      })
      .select("id, title, unread_count")
      .single();
    conversation = created ?? null;
  }

  if (!conversation) {
    return new Response(JSON.stringify({ error: "Conversation not found" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  await supabase.from("messages").insert({
    tenant_id: tenantId,
    conversation_id: conversation.id,
    sender: contactName ?? phone,
    body: messageText,
    is_from_customer: true,
    sent_at: now,
  });

  const unreadCount = (conversation?.unread_count ?? 0) + 1;
  await supabase
    .from("conversations")
    .update({
      last_message: messageText,
      updated_at: now,
      status: "open",
      unread_count: unreadCount,
    })
    .eq("id", conversation.id);

  const { data: botSettings } = await supabase
    .from("bot_settings")
    .select(
      "name, system_prompt, model, temperature, is_active, memory_hours, max_history_messages",
    )
    .eq("tenant_id", tenantId)
    .maybeSingle();

  const isActive = botSettings?.is_active ?? true;
  if (!isActive) {
    return new Response(
      JSON.stringify({ status: "disabled", conversation_id: conversation.id }),
      {
        status: 200,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      },
    );
  }

  const { data: knowledgeEntries } = await supabase
    .from("knowledge_base")
    .select("title, content")
    .eq("tenant_id", tenantId)
    .order("updated_at", { ascending: false })
    .limit(5);

  const knowledgeContext = buildKnowledgeContext(knowledgeEntries ?? []);
  const systemPrompt = (botSettings?.system_prompt ?? defaultPrompt).trim();
  const fullSystemPrompt = knowledgeContext.isEmpty
    ? systemPrompt
    : `${systemPrompt}\n\nBilgi bankasi:\n${knowledgeContext}`;

  const openAiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  if (!openAiKey) {
    return new Response(JSON.stringify({ error: "OpenAI key missing" }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const model = botSettings?.model ?? "gpt-4o-mini";
  const temperature = Number(botSettings?.temperature ?? 0.3);
  const memoryHours = Number(botSettings?.memory_hours ?? defaultMemoryHours);
  const maxHistoryMessages = Number(
    botSettings?.max_history_messages ?? defaultHistoryMessages,
  );

  const cutoff = new Date(Date.now() - memoryHours * 60 * 60 * 1000)
    .toISOString();
  const { data: recentMessages } = await supabase
    .from("messages")
    .select("body, is_from_customer, sent_at")
    .eq("conversation_id", conversation.id)
    .gte("sent_at", cutoff)
    .order("sent_at", { ascending: false })
    .limit(maxHistoryMessages);

  const history = (recentMessages ?? []).reverse().map((item) => ({
    role: item.is_from_customer ? "user" : "assistant",
    content: item.body as string,
  }));

  const aiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${openAiKey}`,
    },
    body: JSON.stringify({
      model,
      temperature,
      max_tokens: 200,
      messages:
        history.length > 0
          ? [{ role: "system", content: fullSystemPrompt }, ...history]
          : [
              { role: "system", content: fullSystemPrompt },
              { role: "user", content: messageText },
            ],
    }),
  });

  if (!aiResponse.ok) {
    const errorText = await aiResponse.text();
    return new Response(JSON.stringify({ error: errorText }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const aiJson = await aiResponse.json();
  const reply = (aiJson?.choices?.[0]?.message?.content as string | undefined)
    ?.trim() ?? "Size nasil yardimci olabilirim?";

  const to = normalizePhone(phone);
  const sendResponse = await fetch(
    `${whatsappBaseUrl}/${whatsappApiVersion}/${activePhoneNumberId}/messages`,
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
        type: "text",
        text: {
          body: reply,
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
  const replyAt = new Date().toISOString();
  const senderName = botSettings?.name ?? "Bot";

  await supabase.from("messages").insert({
    tenant_id: tenantId,
    conversation_id: conversation.id,
    sender: senderName,
    body: reply,
    is_from_customer: false,
    sent_at: replyAt,
    wa_message_id: waMessageId,
    wa_status: "sent",
  });

  await supabase
    .from("conversations")
    .update({ last_message: reply, updated_at: replyAt })
    .eq("id", conversation.id);

  return new Response(
    JSON.stringify({
      status: "ok",
      reply,
      conversation_id: conversation.id,
    }),
    {
      status: 200,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    },
  );
});
