import {
  dispatchOnce,
  type DispatchResult,
} from "../_shared/whatsapp_delivery.ts";
import { ApiError, endpoint, jsonResponse, readBytes } from "../_shared/http.ts";
import { requiredEnv, serviceClient } from "../_shared/supabase.ts";
import { WhatsAppApi } from "../_shared/whatsapp_api.ts";
import { inboxMessagePayload, type OutboundMedia } from "../_shared/inbox_payload.ts";
import {
  connectionToken,
  credentialKeys,
  resolveConnection,
  type WhatsAppConnection,
} from "../_shared/whatsapp_connections.ts";
import { requireWorker } from "../_shared/worker_auth.ts";

type Job = {
  id: string;
  tenant_id: string;
  conversation_id: string;
  connection_id: string;
  recipient_phone: string;
  lease_token: string;
};

Deno.serve(endpoint(async (req) => {
  await requireWorker(req, "INBOX_WORKER_SECRET");
  const version = requiredEnv("WHATSAPP_API_VERSION");
  new WhatsAppApi(version, "configuration-check-only");
  credentialKeys();
  const service = serviceClient();
  const { data, error } = await service.rpc("claim_inbox_dispatches", {
    p_limit: 10,
  });
  if (error) {
    throw new ApiError(
      503,
      "inbox_queue_unavailable",
      "Inbox queue unavailable",
    );
  }
  const jobs = (data ?? []) as Job[];
  const results: DispatchResult[] = [];
  const deadline = Date.now() + 30000;

  async function rpc(
    name: string,
    parameters: Record<string, unknown>,
  ): Promise<boolean> {
    const { data, error } = await service.rpc(name, parameters);
    if (error) {
      throw new ApiError(
        503,
        "queue_write_unavailable",
        "Queue acknowledgement unavailable",
      );
    }
    return data === true;
  }

  async function process(job: Job) {
    const identity = { p_dispatch_id: job.id, p_lease_token: job.lease_token };
    let currentConnection: WhatsAppConnection | undefined;
    return await dispatchOnce({
      prepare: async () => {
        const connection = await resolveConnection(
          service,
          job.tenant_id,
          job.connection_id,
        );
        currentConnection = connection;
        const token = await connectionToken(service, connection);
        const { data: message, error } = await service.from("messages").select(
          "body, provider_content",
        )
          .eq("tenant_id", job.tenant_id).eq(
            "conversation_id",
            job.conversation_id,
          ).eq("id", job.id).single();
        if (error || !message) {
          throw new ApiError(503, "message_unavailable", "Message unavailable");
        }
        const api = new WhatsAppApi(version, token);
        // Media is uploaded to Meta here, before the fenced send starts, so an
        // upload failure defers the job without consuming a send attempt.
        const media = await prepareMedia(api, connection.phone_number_id, job);
        // Bot booking replies carry confirm/cancel buttons (complete_bot_reply).
        const buttons = (message.provider_content as {
          interactive?: { buttons?: { id: string; title: string }[] };
        } | null)?.interactive?.buttons;
        const payload = inboxMessagePayload(
          job.recipient_phone,
          message.body,
          `${job.id}:${job.lease_token}`,
          media,
          Array.isArray(buttons) ? buttons : undefined,
        );
        return () =>
          api.request(`${connection.phone_number_id}/messages`, "POST", payload);
      },
      start: () => rpc("start_inbox_dispatch", identity),
      defer: (code) =>
        rpc("defer_inbox_dispatch", { ...identity, p_code: code }),
      finish: (outcome) =>
        rpc("finish_inbox_dispatch", {
          ...identity,
          p_outcome: outcome.outcome,
          p_provider_message_id: outcome.messageId ?? null,
          p_error_code: outcome.errorCode ?? null,
          p_retry_after_seconds: outcome.retryAfterSeconds ?? 0,
        }),
      authRejected: async () => {
        if (!currentConnection) return;
        await service.from("whatsapp_connections").update({
          status: "needs_attention",
          updated_at: new Date().toISOString(),
        }).eq("tenant_id", job.tenant_id).eq("id", currentConnection.id)
          .eq("updated_at", currentConnection.updated_at);
      },
    });
  }

  async function prepareMedia(
    api: WhatsAppApi,
    phoneNumberId: string,
    job: Job,
  ): Promise<OutboundMedia | undefined> {
    const { data: media, error } = await service.from("message_media")
      .select("kind, direction, storage_path, storage_bucket, mime_type, file_name, caption")
      .eq("tenant_id", job.tenant_id).eq("message_id", job.id).maybeSingle();
    if (error) {
      throw new ApiError(503, "media_unavailable", "Media unavailable");
    }
    if (!media || media.direction !== "outbound") return undefined;
    // Agent files live under the conversation; bot listing photos are catalog photos
    // of the same business.
    const bucket = media.storage_bucket === "catalog-photos" ? "catalog-photos" : "inbox-media";
    const prefix = bucket === "catalog-photos"
      ? `${job.tenant_id}/`
      : `${job.tenant_id}/${job.conversation_id}/outbound/`;
    if (
      (media.kind !== "image" && media.kind !== "document") || !media.storage_path ||
      !String(media.storage_path).startsWith(prefix) ||
      (bucket === "catalog-photos" && media.kind !== "image")
    ) {
      throw new ApiError(503, "media_unavailable", "Media unavailable");
    }
    const { data: file, error: downloadError } = await service.storage
      .from(bucket).download(media.storage_path);
    if (downloadError || !file) {
      throw new ApiError(503, "media_unavailable", "Stored media unavailable");
    }
    const bytes = await readBytes(new Response(file), 16 * 1024 * 1024 + 1);
    const mediaId = await api.uploadMedia(phoneNumberId, {
      bytes,
      mimeType: media.mime_type ?? "application/octet-stream",
      fileName: media.file_name ?? String(media.storage_path).split("/").pop()!,
    });
    return {
      kind: media.kind,
      mediaId,
      caption: media.caption,
      fileName: media.file_name,
    };
  }

  let cursor = 0;
  await Promise.all(
    Array.from({ length: Math.min(5, jobs.length) }, async () => {
      while (cursor < jobs.length && Date.now() < deadline) {
        results.push(await process(jobs[cursor++]));
      }
    }),
  );
  return jsonResponse({
    claimed: jobs.length,
    processed: results.length,
    outcomes: results.reduce<Record<string, number>>((counts, result) => {
      counts[result] = (counts[result] ?? 0) + 1;
      return counts;
    }, {}),
  });
}));
