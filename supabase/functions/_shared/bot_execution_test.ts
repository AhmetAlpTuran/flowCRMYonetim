// Authored only. Pure orchestration fixtures make no database/provider requests.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { AiReplyError, type AiUsage, type BotContext } from "./ai_reply.ts";
import {
  type BotExecutionDependencies,
  executeBotReply,
} from "./bot_execution.ts";

function fixture(overrides: Partial<BotExecutionDependencies> = {}) {
  const context: BotContext = {
    tenant_id: "tenant",
    conversation_id: "conversation",
    input_message_id: "input",
    automation_revision: 1,
    context_revision: 1,
    input: { type: "text", body: "When do you open?" },
    settings: {
      name: "Ava",
      tone: "Professional",
      language: "English",
      system_prompt: "Be concise.",
      model: "gpt-4o-mini",
      temperature: 0.3,
    },
    knowledge: [{ id: "source", title: "Hours", content: "We open at nine." }],
    history: [],
  };
  const calls = {
    generation: 0,
    preparation: [] as (number | null)[],
    settlements: [] as { usage: AiUsage | null; rejected: boolean }[],
    decisions: [] as { action: string; reason: string }[],
    retryDelays: [] as number[],
    retries: 0,
    cancellations: 0,
  };
  const deps: BotExecutionDependencies = {
    allowedModels: new Set(["gpt-4o-mini"]),
    context: () => Promise.resolve(context),
    prepare: (_, request) => {
      calls.preparation.push(request?.reserveTokens ?? null);
      return Promise.resolve("prepared");
    },
    generate: () => {
      calls.generation++;
      return Promise.resolve({
        decision: {
          action: "reply",
          text: "We open at nine.",
          reason: "knowledge_answer",
          knowledge_ids: ["source"],
        },
        usage: { input_tokens: 100, output_tokens: 20, total_tokens: 120 },
        responseId: "resp_fixture",
      });
    },
    settle: (usage, rejected) => {
      calls.settlements.push({ usage, rejected });
      return Promise.resolve(true);
    },
    complete: (decision) => {
      calls.decisions.push(decision);
      return Promise.resolve(true);
    },
    retry: (delaySeconds = 0) => {
      calls.retries++;
      calls.retryDelays.push(delaySeconds);
      return Promise.resolve(true);
    },
    cancel: () => {
      calls.cancellations++;
      return Promise.resolve(true);
    },
    ...overrides,
  };
  return { context, calls, deps };
}

Deno.test("lost settlement and completion acknowledgements never regenerate", async () => {
  const { calls, deps } = fixture();
  const settle = deps.settle;
  deps.settle = async (...args) => {
    await settle(...args);
    if (calls.settlements.length === 1) {
      throw new Error("Lost settlement reply");
    }
    return true;
  };
  const complete = deps.complete;
  deps.complete = async (decision) => {
    await complete(decision);
    if (calls.decisions.length === 1) throw new Error("Lost completion reply");
    return true;
  };
  assertEquals(await executeBotReply(deps), "finalized");
  assertEquals(calls.generation, 1);
  assertEquals(calls.settlements.length, 2);
  assertEquals(calls.decisions.length, 2);
  assertEquals(calls.decisions[0], calls.decisions[1]);
});

Deno.test("missing knowledge and quota exhaustion hand off without generation", async () => {
  const local = fixture();
  local.context.knowledge = [];
  assertEquals(await executeBotReply(local.deps), "finalized");
  assertEquals(local.calls.preparation, [null]);
  assertEquals(local.calls.generation, 0);
  assertEquals(local.calls.settlements.length, 0);
  assertEquals(local.calls.decisions[0].reason, "insufficient_knowledge");
  const quota = fixture({ prepare: () => Promise.resolve("quota_exhausted") });
  assertEquals(await executeBotReply(quota.deps), "finalized");
  assertEquals(quota.calls.generation, 0);
  assertEquals(quota.calls.decisions[0].reason, "ai_budget_exhausted");
});

Deno.test("human takeover preserves usage settlement and suppresses completion", async () => {
  const value = fixture({ complete: () => Promise.resolve(false) });
  assertEquals(await executeBotReply(value.deps), "unconfirmed");
  assertEquals(value.calls.generation, 1);
  assertEquals(value.calls.settlements[0].usage?.total_tokens, 120);
  const stale = fixture({ context: () => Promise.resolve(null) });
  assertEquals(await executeBotReply(stale.deps), "cancelled");
  assertEquals(stale.calls.generation, 0);
});

Deno.test("temporary reservation pressure waits without spending another model call", async () => {
  const value = fixture({ prepare: () => Promise.resolve("quota_pending") });
  assertEquals(await executeBotReply(value.deps), "retry");
  assertEquals(value.calls.generation, 0);
  assertEquals(value.calls.retries, 1);
  assertEquals(value.calls.settlements.length, 0);
});

Deno.test("unknown generation is accounted for and handed off without retry", async () => {
  const value = fixture({
    generate: () => Promise.reject(new AiReplyError("ai_transport_unknown")),
  });
  assertEquals(await executeBotReply(value.deps), "finalized");
  assertEquals(value.calls.settlements, [{ usage: null, rejected: false }]);
  assertEquals(value.calls.retries, 0);
  assertEquals(value.calls.decisions[0].reason, "ai_transport_unknown");
});

Deno.test("definitive throttling releases reservation before bounded retry", async () => {
  const value = fixture({
    generate: () =>
      Promise.reject(
        new AiReplyError("ai_provider_rejected", null, true, true, 90),
      ),
  });
  assertEquals(await executeBotReply(value.deps), "retry");
  assertEquals(value.calls.settlements, [{ usage: null, rejected: true }]);
  assertEquals(value.calls.retries, 1);
  assertEquals(value.calls.retryDelays, [90]);
  assertEquals(value.calls.decisions.length, 0);
});

Deno.test("duplicate preparation cannot trigger another model call", async () => {
  const value = fixture({ prepare: () => Promise.resolve("already_prepared") });
  assertEquals(await executeBotReply(value.deps), "unconfirmed");
  assertEquals(value.calls.generation, 0);
  assertEquals(value.calls.settlements.length, 0);
});

Deno.test("lost preparation response settles a possible unused reservation at zero", async () => {
  const value = fixture({
    prepare: () => Promise.reject(new Error("Lost preparation reply")),
  });
  assertEquals(await executeBotReply(value.deps), "retry");
  assertEquals(value.calls.generation, 0);
  assertEquals(value.calls.settlements, [{ usage: null, rejected: true }]);
});
