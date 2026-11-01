import { ApiError } from "./http.ts";
import { TemplateInputError } from "./template_parameters.ts";

export type DeliveryOutcome = {
  outcome: "accepted" | "failed" | "retry" | "unknown";
  messageId?: string;
  errorCode?: string;
  detail?: string;
  retryAfterSeconds?: number;
  authRejected?: boolean;
};

export async function classifyWhatsAppResponse(
  response: Response,
): Promise<DeliveryOutcome> {
  const payload = await response.json().catch(() => null);
  const id = payload?.messages?.length === 1 ? payload.messages[0]?.id : null;
  if (
    response.ok && !payload?.error && typeof id === "string" &&
    /^wamid\.[^\s]{1,506}$/.test(id)
  ) {
    return { outcome: "accepted", messageId: id };
  }
  const code = payload?.error?.code;
  const definitiveRejection = response.status >= 400 && response.status < 500 &&
    Number.isSafeInteger(code) && code >= 0;
  if (definitiveRejection) {
    // Only explicit provider throttling is retried. A transport/5xx response may
    // have happened after acceptance and must not trigger a duplicate send.
    const retry = response.status === 429 || code === 130429 || code === 131056;
    const header = response.headers.get("Retry-After") ?? "";
    const retryAfter = /^\d+$/.test(header)
      ? Number(header)
      : Math.ceil((Date.parse(header) - Date.now()) / 1000);
    return {
      outcome: retry ? "retry" : "failed",
      errorCode: `meta_${code}`,
      detail: "WhatsApp rejected the message",
      authRejected: code === 190,
      retryAfterSeconds: retry && Number.isFinite(retryAfter)
        ? Math.max(0, Math.min(3600, retryAfter))
        : 0,
    };
  }
  return {
    outcome: "unknown",
    errorCode: "provider_outcome_unknown",
    detail:
      "WhatsApp acceptance was not confirmed; do not automatically resend",
  };
}

export type DispatchDependencies = {
  prepare: () => Promise<() => Promise<Response>>;
  failValidation?: (detail: string) => Promise<boolean>;
  defer: (code: string) => Promise<boolean>;
  start: () => Promise<boolean>;
  finish: (outcome: DeliveryOutcome) => Promise<boolean>;
  authRejected?: () => Promise<void>;
};
export type DispatchResult =
  | DeliveryOutcome["outcome"]
  | "blocked"
  | "skipped"
  | "unconfirmed";

// One external call per successful dispatch marker. Persisting its result can be
// retried independently; this function never retries the external call itself.
export async function dispatchOnce(
  deps: DispatchDependencies,
): Promise<DispatchResult> {
  let send: () => Promise<Response>;
  try {
    send = await deps.prepare();
  } catch (error) {
    try {
      if (error instanceof TemplateInputError && deps.failValidation) {
        return await deps.failValidation(error.message)
          ? "failed"
          : "unconfirmed";
      }
      return await deps.defer(
          error instanceof ApiError ? error.code : "preparation_unavailable",
        )
        ? "blocked"
        : "unconfirmed";
    } catch {
      return "unconfirmed";
    }
  }
  try {
    if (!await deps.start()) return "skipped";
  } catch {
    // If the start committed but its reply was lost, this fenced update cannot
    // touch the sending row; expiry will conservatively surface unknown instead.
    try {
      return await deps.defer("dispatch_start_unavailable")
        ? "blocked"
        : "unconfirmed";
    } catch {
      return "unconfirmed";
    }
  }
  let outcome: DeliveryOutcome;
  try {
    outcome = await classifyWhatsAppResponse(await send());
  } catch {
    outcome = {
      outcome: "unknown",
      errorCode: "transport_outcome_unknown",
      detail:
        "WhatsApp acceptance was not confirmed; do not automatically resend",
    };
  }
  let acknowledged = false;
  for (let attempt = 0; attempt < 2 && !acknowledged; attempt++) {
    try {
      acknowledged = await deps.finish(outcome);
    } catch { /* Retry DB acknowledgement only. */ }
  }
  if (outcome.authRejected && deps.authRejected) {
    try {
      await deps.authRejected();
    } catch { /* The recipient outcome is already recorded. */ }
  }
  return acknowledged ? outcome.outcome : "unconfirmed";
}
