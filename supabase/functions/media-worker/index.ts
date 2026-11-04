import { ApiError, endpoint, jsonResponse } from "../_shared/http.ts";
import {
  downloadWhatsAppMedia,
  mediaExtension,
  MediaTooLargeError,
} from "../_shared/media_download.ts";
import { requiredEnv, serviceClient } from "../_shared/supabase.ts";
import { GraphApiError, WhatsAppApi } from "../_shared/whatsapp_api.ts";
import {
  connectionToken,
  credentialKeys,
  resolveConnection,
} from "../_shared/whatsapp_connections.ts";
import { requireWorker } from "../_shared/worker_auth.ts";

type Job = {
  message_id: string;
  tenant_id: string;
  conversation_id: string;
  connection_id: string;
  provider_media_id: string;
  lease_token: string;
};

// Downloads queued inbound media into the private inbox-media bucket. A few jobs per
// run keep execution bounded; failures retry with backoff (see finish_message_media).
Deno.serve(endpoint(async (req) => {
  await requireWorker(req, "MEDIA_WORKER_SECRET");
  const version = requiredEnv("WHATSAPP_API_VERSION");
  credentialKeys();
  const service = serviceClient();
  const { data, error } = await service.rpc("claim_message_media", {
    p_limit: 3,
  });
  if (error) {
    throw new ApiError(503, "media_queue_unavailable", "Media queue unavailable");
  }
  const outcomes: Record<string, number> = {};
  for (const job of (data ?? []) as Job[]) {
    const outcome = await processJob(service, version, job);
    outcomes[outcome] = (outcomes[outcome] ?? 0) + 1;
  }
  return jsonResponse({ outcomes });
}));

async function processJob(
  service: ReturnType<typeof serviceClient>,
  version: string,
  job: Job,
): Promise<string> {
  const finish = async (
    outcome: "stored" | "retry" | "failed" | "too_large",
    extra: { path?: string; size?: number; mime?: string; code?: string } = {},
  ) => {
    await service.rpc("finish_message_media", {
      p_message_id: job.message_id,
      p_lease_token: job.lease_token,
      p_outcome: outcome,
      p_storage_path: extra.path ?? null,
      p_size_bytes: extra.size ?? null,
      p_mime_type: extra.mime ?? null,
      p_error_code: extra.code ?? null,
    });
    return outcome;
  };
  try {
    const connection = await resolveConnection(
      service,
      job.tenant_id,
      job.connection_id,
    );
    const api = new WhatsAppApi(version, await connectionToken(service, connection));
    const media = await downloadWhatsAppMedia(api, job.provider_media_id);
    const path =
      `${job.tenant_id}/${job.conversation_id}/${job.message_id}.${mediaExtension(media.mimeType)}`;
    const { error } = await service.storage.from("inbox-media").upload(
      path,
      media.bytes,
      { contentType: media.mimeType, upsert: true },
    );
    if (error) return await finish("retry", { code: "storage_unavailable" });
    return await finish("stored", {
      path,
      size: media.bytes.length,
      mime: media.mimeType,
    });
  } catch (error) {
    if (error instanceof MediaTooLargeError) {
      return await finish("too_large", { code: "media_too_large" });
    }
    if (error instanceof GraphApiError) {
      const permanent = error.httpStatus >= 400 && error.httpStatus < 500 &&
        error.httpStatus !== 429 && error.providerCode !== 190;
      return await finish(permanent ? "failed" : "retry", {
        code: error.providerCode === 190 ? "connection_rejected" : `whatsapp_${error.httpStatus}`,
      });
    }
    const code = error instanceof ApiError ? error.code : "media_worker_error";
    // A disconnected or expired number will not recover within the retry window.
    const permanent = code === "invalid_media_id" || code.startsWith("connection_");
    return await finish(permanent ? "failed" : "retry", { code });
  }
}
