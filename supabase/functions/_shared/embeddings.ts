/** OpenAI embeddings for knowledge passages and customer questions (pgvector, 1536 dims). */
export const EMBEDDING_DIMENSIONS = 1536;
export const DEFAULT_EMBEDDING_MODEL = "text-embedding-3-small";

export class EmbeddingError extends Error {
  constructor(readonly code: string, readonly retryable: boolean) {
    super(code);
  }
}

/** The configured model, or null when embeddings are switched off ("off") or invalid. */
export function embeddingModel(value: string | undefined): string | null {
  const model = value?.trim() || DEFAULT_EMBEDDING_MODEL;
  if (model === "off") return null;
  return /^[a-zA-Z0-9_.:-]{1,100}$/.test(model) ? model : null;
}

export function passageText(heading: string | null, content: string): string {
  return heading ? `${heading}\n${content}` : content;
}

export function vectorLiteral(vector: number[]): string {
  return `[${vector.join(",")}]`;
}

export async function embedTexts(
  texts: string[],
  apiKey: string,
  model: string,
  transport: typeof fetch = fetch,
  timeoutMs = 30000,
): Promise<{ vectors: number[][]; tokens: number }> {
  if (!texts.length) return { vectors: [], tokens: 0 };
  let response: Response;
  try {
    response = await transport("https://api.openai.com/v1/embeddings", {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        input: texts,
        encoding_format: "float",
        // Only the text-embedding-3 family can be shortened to the column size.
        ...(model.startsWith("text-embedding-3") ? { dimensions: EMBEDDING_DIMENSIONS } : {}),
      }),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch {
    throw new EmbeddingError("embedding_unavailable", true);
  }
  if (!response.ok) {
    await response.body?.cancel();
    const retryable = response.status === 429 || response.status >= 500;
    throw new EmbeddingError(`embedding_http_${response.status}`, retryable);
  }
  let payload: unknown;
  try {
    payload = await response.json();
  } catch {
    throw new EmbeddingError("embedding_invalid_response", true);
  }
  const data = (payload as { data?: unknown }).data;
  const usage = (payload as { usage?: { total_tokens?: unknown } }).usage;
  if (!Array.isArray(data) || data.length !== texts.length) {
    throw new EmbeddingError("embedding_invalid_response", true);
  }
  const vectors: number[][] = new Array(texts.length);
  for (const item of data as { index?: unknown; embedding?: unknown }[]) {
    const index = item?.index;
    const embedding = item?.embedding;
    if (
      typeof index !== "number" || !Number.isInteger(index) || index < 0 ||
      index >= texts.length || vectors[index] !== undefined ||
      !Array.isArray(embedding) || embedding.length !== EMBEDDING_DIMENSIONS ||
      !embedding.every((n) => typeof n === "number" && Number.isFinite(n))
    ) {
      throw new EmbeddingError("embedding_invalid_response", false);
    }
    vectors[index] = embedding as number[];
  }
  const tokens = typeof usage?.total_tokens === "number" && Number.isSafeInteger(usage.total_tokens) &&
      usage.total_tokens >= 0
    ? usage.total_tokens
    : texts.reduce((sum, text) => sum + Math.ceil(text.length / 3), 0);
  return { vectors, tokens };
}
