import { type BotContext, generateAiReply } from "../_shared/ai_reply.ts";
import {
  bookingButtons,
  buttonReplyText,
  type ButtonTap,
  catalogToolDefinitions,
  type CatalogType,
  createToolRunner,
  istanbulToday,
  parseButtonTap,
  parsePeriod,
  type ToolRunner,
  trackHolds,
} from "../_shared/bot_tools.ts";
import {
  type BotExecutionResult,
  executeBotReply,
} from "../_shared/bot_execution.ts";
import { ApiError, endpoint, jsonResponse } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { requireWorker } from "../_shared/worker_auth.ts";

type Job = { id: string; lease_token: string };

Deno.serve(endpoint(async (req) => {
  await requireWorker(req, "BOT_WORKER_SECRET");
  const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim() ?? "";
  const limitText = Deno.env.get("AI_MONTHLY_TOKEN_LIMIT")?.trim() ?? "";
  const limitValue = Number(limitText);
  const validLimit = /^\d+$/.test(limitText) &&
    Number.isSafeInteger(limitValue) &&
    limitValue >= 0 && limitValue <= 1000000000000;
  const defaultLimit = validLimit ? limitValue : 0;
  // Configuration failure routes affected conversations to humans without a paid
  // generation call. Deployment monitoring also receives the readiness flag.
  const allowedModels = new Set(
    apiKey && validLimit
      ? (Deno.env.get("OPENAI_ALLOWED_MODELS") ?? "gpt-4o-mini").split(",").map(
        (model) => model.trim(),
      ).filter(Boolean)
      : [],
  );
  const service = serviceClient();
  async function rpc(name: string, parameters: Record<string, unknown>) {
    const { data, error } = await service.rpc(name, parameters);
    if (error) {
      throw new ApiError(503, "bot_queue_unavailable", "Bot queue unavailable");
    }
    return data;
  }
  const staleReservations = await rpc("mark_stale_ai_reservations", {
    p_limit: 100,
  });
  const deliveryReconciliation = await rpc("reconcile_bot_delivery_failures", {
    p_limit: 20,
  });
  const settled = await Promise.allSettled(
    Array.from(
      { length: 3 },
      async (): Promise<BotExecutionResult | "idle"> => {
        const claimed = await rpc("claim_bot_reply", {}) as Job[];
        const job = claimed?.[0];
        if (!job) return "idle";
        const identity = { p_job_id: job.id, p_lease_token: job.lease_token };
        let scope: { tenantId: string; conversationId: string } | null = null;
        let tap: ButtonTap | null = null;
        let held: () => string[] = () => [];
        return await executeBotReply({
          allowedModels,
          toolset: async (context) => {
            scope = { tenantId: context.tenant_id, conversationId: context.conversation_id };
            if (context.input.type === "interactive") {
              const { data: input } = await service.from("messages").select("provider_content")
                .eq("tenant_id", context.tenant_id).eq("id", context.input_message_id).maybeSingle();
              tap = parseButtonTap((input as { provider_content?: unknown } | null)?.provider_content);
            }
            const { data, error } = await service.from("resource_types")
              .select("key, name, kind, booking_unit, fields")
              .eq("tenant_id", context.tenant_id).limit(20);
            if (error || !data?.length) return undefined;
            return {
              definitions: catalogToolDefinitions(data as CatalogType[]),
              today: istanbulToday(),
            };
          },
          context: async () =>
            await rpc("bot_reply_context", identity) as BotContext | null,
          prepare: async (context, request) =>
            await rpc("prepare_bot_reply", {
              ...identity,
              p_automation_revision: context.automation_revision,
              p_context_revision: context.context_revision,
              p_model: request ? context.settings.model : null,
              p_reserve_tokens: request?.reserveTokens ?? 0,
              p_default_limit: defaultLimit,
            }) as string,
          generate: async (request) => {
            const base: ToolRunner | undefined = scope && request.toolsEnabled
              ? createToolRunner({
                rpc: async (name, params) => {
                  const { data, error } = await service.rpc(name, params);
                  return { data, error };
                },
                resourceUnit: async (resourceId) => {
                  const { data } = await service.from("resources")
                    .select("type:resource_types(kind, booking_unit)")
                    .eq("tenant_id", scope!.tenantId).eq("id", resourceId).maybeSingle();
                  const type = (data as { type?: { kind?: string; booking_unit?: string } } | null)?.type;
                  return type?.kind === "bookable" ? type.booking_unit : null;
                },
                conversationBookings: async () => {
                  const { data } = await service.from("bookings")
                    .select("id, status, period, hold_expires_at, resource:resources(name)")
                    .eq("tenant_id", scope!.tenantId).eq("conversation_id", scope!.conversationId)
                    .neq("status", "cancelled").order("created_at", { ascending: false }).limit(5);
                  return data ?? [];
                },
              }, { ...scope, jobId: job.id })
              : undefined;
            if (tap && base) {
              // A tapped Onayla/İptal button is applied directly, without a model call.
              const result = await base({
                call_id: "button",
                name: tap.action === "confirm" ? "confirm_booking" : "cancel_booking",
                arguments: JSON.stringify({ booking_id: tap.bookingId }),
              });
              const { data: booking } = await service.from("bookings")
                .select("period, resource:resources(name)")
                .eq("tenant_id", scope!.tenantId).eq("id", tap.bookingId).maybeSingle();
              const row = booking as { period?: string; resource?: { name?: string } } | null;
              return {
                decision: {
                  action: "reply",
                  text: buttonReplyText(tap, result, {
                    name: row?.resource?.name,
                    ...(parsePeriod(row?.period) ?? {}),
                  }),
                  reason: "tool_answer",
                  knowledge_ids: [],
                },
                usage: { input_tokens: 0, output_tokens: 0, total_tokens: 0 },
                responseId: "button_tap",
              };
            }
            const tracked = base ? trackHolds(base) : undefined;
            held = tracked?.held ?? (() => []);
            return await generateAiReply(request, apiKey, fetch, tracked?.runner);
          },
          settle: async (usage, rejected, responseId) =>
            await rpc("settle_bot_usage", {
              ...identity,
              p_usage: usage,
              p_rejected: rejected,
              p_response_id: responseId ?? null,
            }) === true,
          complete: async (decision) => {
            const buttons = decision.action === "reply" && [...decision.text].length <= 1024
              ? bookingButtons(held())
              : undefined;
            return await rpc("complete_bot_reply", {
              ...identity,
              p_decision: buttons ? { ...decision, buttons } : decision,
            }) === true;
          },
          retry: async (delaySeconds = 0) =>
            await rpc("retry_bot_reply", {
              ...identity,
              p_retry_after_seconds: delaySeconds,
            }) === true,
          cancel: async () => await rpc("cancel_bot_reply", identity) === true,
        });
      },
    ),
  );
  const outcomes = settled.map((result) =>
    result.status === "fulfilled" ? result.value : "unconfirmed"
  );
  return jsonResponse({
    delivery_reconciliation: deliveryReconciliation,
    stale_reservations: staleReservations,
    configuration_ready: Boolean(apiKey && validLimit && allowedModels.size),
    outcomes: outcomes.reduce<Record<string, number>>((counts, outcome) => {
      counts[outcome] = (counts[outcome] ?? 0) + 1;
      return counts;
    }, {}),
  });
}));
