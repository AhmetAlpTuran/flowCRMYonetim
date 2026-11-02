// Authored for deferred verification. Every transport is injected and uses fixtures.
import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  AiReplyError,
  type BotContext,
  generateAiReply,
  localBotDecision,
  parseAiReply,
  prepareAiRequest,
} from "./ai_reply.ts";

const context = (): BotContext => ({
  tenant_id: "private-tenant",
  conversation_id: "private-conversation",
  input_message_id: "private-input",
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
  knowledge: [{ id: "kb-a", title: "Hours", content: "We open at 9am." }],
  history: [{ role: "user", body: "Hello" }],
});
const decision = () => ({
  action: "reply",
  text: "We open at 9am.",
  reason: "knowledge_answer",
  knowledge_ids: ["kb-a"],
});
function response(output: unknown = decision()) {
  return {
    id: "resp_fixture",
    status: "completed",
    error: null,
    incomplete_details: null,
    output: [{
      type: "message",
      role: "assistant",
      status: "completed",
      content: [{ type: "output_text", text: JSON.stringify(output) }],
    }],
    usage: { input_tokens: 100, output_tokens: 40, total_tokens: 140 },
  };
}
const models = new Set(["gpt-4o-mini"]);

Deno.test("request uses strict structured output, bounded response and no stored conversation", () => {
  const prepared = prepareAiRequest(context(), models);
  const payload = JSON.parse(prepared.body);
  assertEquals(payload.model, "gpt-4o-mini");
  assertEquals(payload.store, false);
  assertEquals(payload.tools, []);
  assertEquals(payload.max_output_tokens, 1600);
  assertEquals(payload.text.format.strict, true);
  assertEquals(payload.text.format.schema.additionalProperties, false);
  assertEquals(prepared.body.includes("private-tenant"), false);
  assertEquals(prepared.body.includes("private-conversation"), false);
  assertEquals(prepared.body.includes("private-input"), false);
  assertEquals(
    prepared.reserveTokens,
    new TextEncoder().encode(prepared.body).length + 5696,
  );
});

Deno.test("unsupported input and missing knowledge produce local handoff decisions", () => {
  const value = context();
  value.input.type = "audio";
  assertEquals(localBotDecision(value)?.reason, "unsupported_request");
  value.input.type = "text";
  value.knowledge = [];
  assertEquals(localBotDecision(value)?.reason, "insufficient_knowledge");
});

Deno.test("old history is bounded and oversized current context fails before generation", () => {
  const value = context();
  value.history = Array.from(
    { length: 50 },
    (_, index) => ({ role: "user", body: `${index}:` + "İ".repeat(2000) }),
  );
  const payload = JSON.parse(prepareAiRequest(value, models).body);
  const data = JSON.parse(payload.input[0].content);
  assertEquals(data.history.length < 50, true);
  assertEquals(data.customer_message, value.input.body);
  value.settings.system_prompt = "x".repeat(110000);
  assertThrows(
    () => prepareAiRequest(value, models),
    AiReplyError,
    "ai_context_too_large",
  );
  assertThrows(
    () => prepareAiRequest(context(), new Set()),
    AiReplyError,
    "ai_configuration_invalid",
  );
});

Deno.test("only current knowledge IDs and coherent actions are accepted", () => {
  assertEquals(
    parseAiReply(response(), new Set(["kb-a"])).decision.text,
    "We open at 9am.",
  );
  assertThrows(() => parseAiReply(response(), new Set(["kb-b"])), AiReplyError);
  assertThrows(
    () =>
      parseAiReply(
        response({ ...decision(), knowledge_ids: [] }),
        new Set(["kb-a"]),
      ),
    AiReplyError,
  );
  assertThrows(
    () =>
      parseAiReply(
        response({ ...decision(), recipient: "another customer" }),
        new Set(["kb-a"]),
      ),
    AiReplyError,
  );
  assertThrows(
    () =>
      parseAiReply(
        response({ ...decision(), action: "handoff" }),
        new Set(["kb-a"]),
      ),
    AiReplyError,
  );
  assertThrows(
    () =>
      parseAiReply(
        response({ ...decision(), text: "x".repeat(4097) }),
        new Set(["kb-a"]),
      ),
    AiReplyError,
  );
  assertEquals(
    parseAiReply(
      response({
        action: "handoff",
        text: "",
        reason: "human_requested",
        knowledge_ids: [],
      }),
      new Set(),
    ).decision.action,
    "handoff",
  );
});

Deno.test("refused and incomplete responses preserve measured usage for settlement", () => {
  const incomplete = { ...response(), status: "incomplete" };
  const incompleteError = assertThrows(
    () => parseAiReply(incomplete, new Set(["kb-a"])),
    AiReplyError,
  );
  assertEquals(incompleteError.usage?.total_tokens, 140);
  const refused = {
    ...response(),
    output: [{
      type: "message",
      role: "assistant",
      status: "completed",
      content: [{ type: "refusal", refusal: "fixture" }],
    }],
  };
  const refusalError = assertThrows(
    () => parseAiReply(refused, new Set()),
    AiReplyError,
    "ai_refused",
  );
  assertEquals(refusalError.usage?.total_tokens, 140);
  assertThrows(
    () =>
      parseAiReply({
        ...response(),
        usage: { input_tokens: 100, output_tokens: 40, total_tokens: 1 },
      }, new Set(["kb-a"])),
    AiReplyError,
  );
});

Deno.test("transport errors and throttling never cause an internal generation retry", async () => {
  const prepared = prepareAiRequest(context(), models);
  let calls = 0;
  const unavailable: typeof fetch = () => {
    calls++;
    return Promise.reject(new Error("Fixture network failure"));
  };
  const unknown = await assertRejects(
    () => generateAiReply(prepared, "fixture", unavailable),
    AiReplyError,
    "ai_transport_unknown",
  );
  assertEquals(unknown.rejected, false);
  assertEquals(calls, 1);
  const throttled: typeof fetch = () => {
    calls++;
    return Promise.resolve(
      new Response(JSON.stringify({ error: { code: "rate_limit_exceeded" } }), {
        status: 429,
        headers: { "Retry-After": "120" },
      }),
    );
  };
  const rejection = await assertRejects(
    () => generateAiReply(prepared, "fixture", throttled),
    AiReplyError,
  );
  assertEquals(rejection.rejected, true);
  assertEquals(rejection.retryable, true);
  assertEquals(rejection.retryAfterSeconds, 120);
  assertEquals(calls, 2);
});

Deno.test("billing failures and excessive retry hints never trigger automatic generation retries", async () => {
  const prepared = prepareAiRequest(context(), models);
  for (
    const code of [
      "insufficient_quota",
      "credit_balance_exhausted",
      "organization_spend_limit_exceeded",
      "project_spend_limit_exceeded",
    ]
  ) {
    const transport: typeof fetch = () =>
      Promise.resolve(
        new Response(
          JSON.stringify({ error: { code, type: "rate_limit_error" } }),
          { status: 429 },
        ),
      );
    const failure = await assertRejects(
      () => generateAiReply(prepared, "fixture", transport),
      AiReplyError,
    );
    assertEquals(failure.retryable, false);
    assertEquals(failure.rejected, true);
  }
  for (const delay of ["7200", "9".repeat(400)]) {
    const transport: typeof fetch = () =>
      Promise.resolve(
        new Response(JSON.stringify({ error: { code: "slow_down" } }), {
          status: 429,
          headers: { "Retry-After": delay },
        }),
      );
    const failure = await assertRejects(
      () => generateAiReply(prepared, "fixture", transport),
      AiReplyError,
      "ai_retry_delay_exceeded",
    );
    assertEquals(failure.retryable, false);
  }
});

Deno.test("provider requests use the fixed host and never follow redirects", async () => {
  const transport: typeof fetch = (url, options) => {
    assertEquals(url, "https://api.openai.com/v1/responses");
    assertEquals(options?.redirect, "error");
    return Promise.resolve(
      new Response(JSON.stringify(response()), {
        headers: { "content-type": "application/json" },
      }),
    );
  };
  assertEquals(
    (await generateAiReply(
      prepareAiRequest(context(), models),
      "fixture",
      transport,
    )).usage.total_tokens,
    140,
  );
});
