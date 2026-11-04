import type { BotContext } from "./ai_reply.ts";
import { vectorLiteral } from "./embeddings.ts";

type Rpc = (
  name: string,
  params: Record<string, unknown>,
) => Promise<{ data: unknown; error: unknown }>;
type Knowledge = BotContext["knowledge"];

export type KnowledgeSearchDeps = {
  rpc: Rpc;
  /** Embeds the customer's question; absent when embeddings are not configured. */
  embed?: (text: string) => Promise<{ vector: number[]; tokens: number }>;
  model: string | null;
};

function validKnowledge(data: unknown): Knowledge | null {
  if (!Array.isArray(data)) return null;
  const items = data.filter((item): item is Knowledge[number] =>
    typeof item?.id === "string" && typeof item?.title === "string" &&
    typeof item?.content === "string"
  );
  return items.length === data.length ? items.slice(0, 5) : null;
}

/**
 * Knowledge for the bot: hybrid full-text + vector search over manual entries and
 * document passages (bot_knowledge_search). An embedding failure falls back to
 * full-text search, and a search failure keeps the context's own entries.
 */
export async function searchKnowledge(
  context: BotContext,
  identity: { p_job_id: string; p_lease_token: string },
  deps: KnowledgeSearchDeps,
): Promise<Knowledge> {
  const question = (context.input.body ?? "").trim();
  let params: Record<string, unknown> = { ...identity };
  if (deps.embed && deps.model && question.replace(/\s/g, "").length >= 3) {
    try {
      const { vector, tokens } = await deps.embed(question.slice(0, 4000));
      params = {
        ...identity,
        p_query_embedding: vectorLiteral(vector),
        p_embedding_model: deps.model,
        p_embedding_tokens: tokens,
      };
    } catch {
      // Full-text search only.
    }
  }
  try {
    let result = await deps.rpc("bot_knowledge_search", params);
    if (result.error && "p_query_embedding" in params) {
      result = await deps.rpc("bot_knowledge_search", { ...identity });
    }
    if (result.error) return context.knowledge;
    return validKnowledge(result.data) ?? context.knowledge;
  } catch {
    return context.knowledge;
  }
}
