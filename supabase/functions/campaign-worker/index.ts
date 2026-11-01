import {
  type DeliveryOutcome,
  dispatchOnce,
  type DispatchResult,
} from "../_shared/whatsapp_delivery.ts";
import {
  ApiError,
  endpoint,
  jsonResponse,
  readJson,
  uuid,
} from "../_shared/http.ts";
import { requiredEnv, serviceClient } from "../_shared/supabase.ts";
import {
  buildTemplateComponents,
  type ContactValues,
} from "../_shared/template_parameters.ts";
import { WhatsAppApi } from "../_shared/whatsapp_api.ts";
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
  campaign_id: string;
  lease_token: string;
  recipient_phone: string;
  contact_snapshot: ContactValues;
};
type Snapshot = {
  connection_id: string;
  connection: { id: string; waba_id: string; phone_number_id: string };
  template: { name: string; language: string; components: unknown };
  template_bindings: unknown;
};

Deno.serve(endpoint(async (req) => {
  await requireWorker(req);
  const body = await readJson(req, 4096);
  const campaignId = body.campaign_id === undefined
    ? null
    : uuid(body.campaign_id, "Campaign ID");
  const version = requiredEnv("WHATSAPP_API_VERSION");
  new WhatsAppApi(version, "configuration-check-only");
  credentialKeys();
  const service = serviceClient();
  const { data, error } = await service.rpc("claim_campaign_dispatches", {
    p_limit: 10,
    p_campaign_id: campaignId,
  });
  if (error) {
    throw new ApiError(503, "claim_failed", "Campaign queue unavailable");
  }
  const jobs = (data ?? []) as Job[];
  const snapshots = new Map<string, Promise<Snapshot>>();
  const connections = new Map<
    string,
    Promise<{ connection: WhatsAppConnection; token: string }>
  >();
  const results: DispatchResult[] = [];
  const deadline = Date.now() + 30000;

  function snapshotFor(job: Job): Promise<Snapshot> {
    const key = `${job.tenant_id}:${job.campaign_id}`;
    if (!snapshots.has(key)) {
      snapshots.set(
        key,
        (async () => {
          const { data, error } = await service.from("campaigns").select(
            "send_snapshot",
          )
            .eq("tenant_id", job.tenant_id).eq("id", job.campaign_id).single();
          if (error || !data?.send_snapshot?.connection?.id) {
            throw new ApiError(
              409,
              "snapshot_unavailable",
              "Campaign snapshot unavailable",
            );
          }
          return data.send_snapshot as Snapshot;
        })(),
      );
    }
    return snapshots.get(key)!;
  }

  function connectionFor(job: Job, snapshot: Snapshot) {
    const key = `${job.tenant_id}:${snapshot.connection.id}`;
    if (!connections.has(key)) {
      connections.set(
        key,
        (async () => {
          const connection = await resolveConnection(
            service,
            job.tenant_id,
            snapshot.connection.id,
          );
          if (
            connection.waba_id !== snapshot.connection.waba_id ||
            connection.phone_number_id !== snapshot.connection.phone_number_id
          ) {
            throw new ApiError(
              409,
              "connection_snapshot_mismatch",
              "Campaign connection changed",
            );
          }
          return {
            connection,
            token: await connectionToken(service, connection),
          };
        })(),
      );
    }
    return connections.get(key)!;
  }

  async function rpcBoolean(
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

  async function process(job: Job): Promise<DispatchResult> {
    const identity = { p_dispatch_id: job.id, p_lease_token: job.lease_token };
    let currentConnection: WhatsAppConnection | undefined;
    return await dispatchOnce({
      prepare: async () => {
        const snapshot = await snapshotFor(job);
        const components = buildTemplateComponents(
          snapshot.template.components,
          snapshot.template_bindings,
          job.contact_snapshot,
        );
        const { connection, token } = await connectionFor(job, snapshot);
        currentConnection = connection;
        const api = new WhatsAppApi(version, token);
        const payload = {
          messaging_product: "whatsapp",
          recipient_type: "individual",
          to: job.recipient_phone,
          type: "template",
          biz_opaque_callback_data: `${job.id}:${job.lease_token}`,
          template: {
            name: snapshot.template.name,
            language: { code: snapshot.template.language },
            ...(components.length ? { components } : {}),
          },
        };
        return () =>
          api.request(
            `${connection.phone_number_id}/messages`,
            "POST",
            payload,
          );
      },
      start: () => rpcBoolean("start_campaign_dispatch", identity),
      failValidation: (detail) =>
        rpcBoolean("fail_campaign_validation", {
          ...identity,
          p_detail: detail,
        }),
      defer: (code) =>
        rpcBoolean("defer_campaign_dispatch", { ...identity, p_code: code }),
      finish: (outcome: DeliveryOutcome) =>
        rpcBoolean("finish_campaign_dispatch", {
          ...identity,
          p_outcome: outcome.outcome,
          p_provider_message_id: outcome.messageId ?? null,
          p_error_code: outcome.errorCode ?? null,
          p_detail: outcome.detail ?? null,
          p_retry_after_seconds: outcome.retryAfterSeconds ?? 0,
        }),
      authRejected: async () => {
        if (!currentConnection) return;
        await service.from("whatsapp_connections").update({
          status: "needs_attention",
          updated_at: new Date().toISOString(),
        })
          .eq("id", currentConnection.id).eq("tenant_id", job.tenant_id).eq(
            "updated_at",
            currentConnection.updated_at,
          );
      },
    });
  }

  let cursor = 0;
  await Promise.all(
    Array.from({ length: Math.min(5, jobs.length) }, async () => {
      while (cursor < jobs.length && Date.now() < deadline) {
        const job = jobs[cursor++];
        results.push(await process(job));
      }
    }),
  );
  // Any unstarted claims expire safely. Lost post-dispatch acknowledgements are
  // reclassified unknown by the next claim sweep, never automatically resent.
  await Promise.all(
    [...new Set(jobs.map((job) => job.campaign_id))].map(async (id) => {
      const { error } = await service.rpc("refresh_campaign_progress", {
        p_campaign_id: id,
      });
      if (error) {
        console.error(
          JSON.stringify({
            code: "campaign_progress_refresh_failed",
            campaign_id: id,
          }),
        );
      }
    }),
  );
  const counts = Object.fromEntries(
    [
      "accepted",
      "failed",
      "retry",
      "unknown",
      "blocked",
      "skipped",
      "unconfirmed",
    ]
      .map((state) => [
        state,
        results.filter((result) => result === state).length,
      ]),
  );
  return jsonResponse({
    status: counts.unknown || counts.unconfirmed ? "attention" : "ok",
    claimed: jobs.length,
    processed: results.length,
    ...counts,
  });
}));
