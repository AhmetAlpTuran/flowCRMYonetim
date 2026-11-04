import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { BotContext } from "./ai_reply.ts";
import { embeddingModel, EmbeddingError, embedTexts, vectorLiteral } from "./embeddings.ts";
import { searchKnowledge } from "./knowledge_search.ts";

const vector = (seed: number) => Array.from({ length: 1536 }, (_, i) => (i === seed ? 1 : 0));
const identity = { p_job_id: "job", p_lease_token: "lease" };
const context = {
  input: { type: "text", body: "Kahvaltı saat kaçta?" },
  knowledge: [{ id: "own", title: "Eski", content: "Bağlamdaki kayıt" }],
} as unknown as BotContext;
const found = [{ id: "c1", title: "Otel – Sayfa 2", content: "Kahvaltı 08:00-10:30" }];

Deno.test("embedTexts sends the model and dimensions and orders vectors by index", async () => {
  let sent: Record<string, unknown> = {};
  const transport = (async (_url: string, init?: RequestInit) => {
    sent = JSON.parse(String(init?.body));
    return new Response(JSON.stringify({
      data: [{ index: 1, embedding: vector(1) }, { index: 0, embedding: vector(0) }],
      usage: { prompt_tokens: 9, total_tokens: 9 },
    }));
  }) as typeof fetch;
  const result = await embedTexts(["a", "b"], "key", "text-embedding-3-small", transport);
  assertEquals(sent, {
    model: "text-embedding-3-small",
    input: ["a", "b"],
    encoding_format: "float",
    dimensions: 1536,
  });
  assertEquals(result.tokens, 9);
  assertEquals(result.vectors[0][0], 1);
  assertEquals(result.vectors[1][1], 1);
  assertEquals(vectorLiteral([1, 0.5, -2]), "[1,0.5,-2]");
});

Deno.test("embedTexts classifies provider failures", async () => {
  const respond = (status: number, body: unknown = {}) =>
    (async () => new Response(JSON.stringify(body), { status })) as typeof fetch;
  const busy = await assertRejects(() => embedTexts(["a"], "k", "m", respond(429)), EmbeddingError);
  assertEquals([busy.code, busy.retryable], ["embedding_http_429", true]);
  const denied = await assertRejects(() => embedTexts(["a"], "k", "m", respond(401)), EmbeddingError);
  assertEquals(denied.retryable, false);
  const short = await assertRejects(
    () => embedTexts(["a"], "k", "m", respond(200, { data: [{ index: 0, embedding: [1, 2] }] })),
    EmbeddingError,
  );
  assertEquals(short.code, "embedding_invalid_response");
  assertEquals(embeddingModel(undefined), "text-embedding-3-small");
  assertEquals(embeddingModel(" off "), null);
  assertEquals(embeddingModel("bad model"), null);
});

Deno.test("searchKnowledge sends the question's embedding and records its tokens", async () => {
  const calls: Record<string, unknown>[] = [];
  const knowledge = await searchKnowledge(context, identity, {
    model: "text-embedding-3-small",
    embed: async (text) => {
      assertEquals(text, "Kahvaltı saat kaçta?");
      return { vector: [0.25, 0.5], tokens: 7 };
    },
    rpc: async (name, params) => {
      assertEquals(name, "bot_knowledge_search");
      calls.push(params);
      return { data: found, error: null };
    },
  });
  assertEquals(knowledge, found);
  assertEquals(calls, [{
    ...identity,
    p_query_embedding: "[0.25,0.5]",
    p_embedding_model: "text-embedding-3-small",
    p_embedding_tokens: 7,
  }]);
});

Deno.test("searchKnowledge falls back to full-text search, then to the context", async () => {
  const calls: Record<string, unknown>[] = [];
  const failingEmbed = async () => {
    throw new EmbeddingError("embedding_unavailable", true);
  };
  assertEquals(
    await searchKnowledge(context, identity, {
      model: "m",
      embed: failingEmbed,
      rpc: async (_name, params) => {
        calls.push(params);
        return { data: found, error: null };
      },
    }),
    found,
  );
  assertEquals(calls, [identity]);

  // A search error with an embedding retries once without it.
  const attempts: Record<string, unknown>[] = [];
  assertEquals(
    await searchKnowledge(context, identity, {
      model: "m",
      embed: async () => ({ vector: [1], tokens: 1 }),
      rpc: async (_name, params) => {
        attempts.push(params);
        return attempts.length === 1 ? { data: null, error: { code: "22023" } } : { data: found, error: null };
      },
    }),
    found,
  );
  assertEquals(attempts[1], identity);

  // Errors and malformed rows keep the context's own knowledge.
  const own = context.knowledge;
  assertEquals(
    await searchKnowledge(context, identity, { model: null, rpc: async () => ({ data: null, error: {} }) }),
    own,
  );
  assertEquals(
    await searchKnowledge(context, identity, { model: null, rpc: async () => ({ data: [{ id: 1 }], error: null }) }),
    own,
  );
  assertEquals(
    await searchKnowledge(context, identity, {
      model: null,
      rpc: async () => {
        throw new Error("network");
      },
    }),
    own,
  );
});
