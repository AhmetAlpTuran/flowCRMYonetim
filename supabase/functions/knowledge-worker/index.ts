import {
  chunkSections,
  DocumentError,
  extractDocument,
} from "../_shared/document_text.ts";
import {
  embeddingModel,
  EmbeddingError,
  embedTexts,
  passageText,
} from "../_shared/embeddings.ts";
import { ApiError, endpoint, jsonResponse } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { requireWorker } from "../_shared/worker_auth.ts";

type Service = ReturnType<typeof serviceClient>;
type DocumentJob = {
  id: string;
  tenant_id: string;
  format: string;
  storage_path: string;
  lease_token: string;
};
type Passage = {
  id: string;
  tenant_id: string;
  heading: string | null;
  content: string;
  content_hash: string;
};

const MAX_FILE_BYTES = 10 * 1024 * 1024;
const EMBED_BATCH = 32;

// Scheduled worker: extracts one queued knowledge document per run into passages,
// then embeds passages that have no embedding yet (documents and manual entries).
Deno.serve(endpoint(async (req) => {
  await requireWorker(req, "KNOWLEDGE_WORKER_SECRET");
  const service = serviceClient();
  const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim() ?? "";
  const model = embeddingModel(Deno.env.get("OPENAI_EMBEDDING_MODEL"));
  const document = await processDocument(service);
  const embeddings = apiKey && model
    ? await embedPassages(service, apiKey, model)
    : { skipped: "embeddings_not_configured" };
  return jsonResponse({ document, embeddings });
}));

async function processDocument(service: Service): Promise<string> {
  const { data, error } = await service.rpc("claim_knowledge_document", {});
  if (error) {
    throw new ApiError(503, "knowledge_queue_unavailable", "Knowledge queue unavailable");
  }
  const job = (data as DocumentJob[] | null)?.[0];
  if (!job) return "idle";
  const finish = async (
    outcome: "ready" | "retry" | "failed",
    extra: { chunks?: unknown; pages?: number | null; code?: string } = {},
  ) => {
    const { data: finished, error: finishError } = await service.rpc(
      "finish_knowledge_document",
      {
        p_document_id: job.id,
        p_lease_token: job.lease_token,
        p_outcome: outcome,
        p_chunks: extra.chunks ?? null,
        p_page_count: extra.pages ?? null,
        p_error_code: extra.code ?? null,
      },
    );
    return !finishError && finished === true ? outcome : "unconfirmed";
  };
  const { data: file, error: downloadError } = await service.storage
    .from("knowledge-documents").download(job.storage_path);
  if (downloadError || !file) {
    const status = Number(
      (downloadError as { status?: number; statusCode?: string } | null)?.status ??
        (downloadError as { statusCode?: string } | null)?.statusCode,
    );
    return await finish(status === 400 || status === 404 ? "failed" : "retry", {
      code: "file_missing",
    });
  }
  if (file.size > MAX_FILE_BYTES) return await finish("failed", { code: "too_large" });
  try {
    const extracted = await extractDocument(job.format, new Uint8Array(await file.arrayBuffer()));
    const chunks = chunkSections(extracted.sections);
    return await finish("ready", { chunks, pages: extracted.pages });
  } catch (cause) {
    if (cause instanceof DocumentError) return await finish("failed", { code: cause.code });
    return await finish("retry");
  }
}

async function embedPassages(
  service: Service,
  apiKey: string,
  model: string,
): Promise<Record<string, number | string>> {
  const { data, error } = await service.rpc("claim_knowledge_embeddings", {
    p_model: model,
    p_limit: 64,
  });
  if (error) return { error: "embedding_queue_unavailable" };
  const passages = (data ?? []) as Passage[];
  const byTenant = new Map<string, Passage[]>();
  for (const passage of passages) {
    byTenant.set(passage.tenant_id, [...(byTenant.get(passage.tenant_id) ?? []), passage]);
  }
  let saved = 0;
  let failed = 0;
  for (const [tenantId, group] of byTenant) {
    for (let start = 0; start < group.length; start += EMBED_BATCH) {
      const batch = group.slice(start, start + EMBED_BATCH);
      try {
        const { vectors, tokens } = await embedTexts(
          batch.map((p) => passageText(p.heading, p.content)),
          apiKey,
          model,
        );
        const { data: count, error: saveError } = await service.rpc("save_knowledge_embeddings", {
          p_tenant_id: tenantId,
          p_model: model,
          p_tokens: tokens,
          p_items: batch.map((p, index) => ({
            id: p.id,
            content_hash: p.content_hash,
            embedding: vectors[index],
          })),
        });
        if (saveError) failed += batch.length;
        else saved += Number(count ?? 0);
      } catch (cause) {
        // Claimed passages are retried later with backoff.
        failed += batch.length;
        if (cause instanceof EmbeddingError && !cause.retryable) {
          return { claimed: passages.length, saved, failed, error: cause.code };
        }
      }
    }
  }
  return { claimed: passages.length, saved, failed };
}
