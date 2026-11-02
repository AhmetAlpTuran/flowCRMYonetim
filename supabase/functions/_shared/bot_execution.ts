import {
  type AiReply,
  AiReplyError,
  type AiUsage,
  type BotContext,
  localBotDecision,
  prepareAiRequest,
} from "./ai_reply.ts";

type Decision = {
  action: "reply" | "handoff";
  text: string;
  reason: string;
  knowledge_ids: string[];
};
type PreparedRequest = ReturnType<typeof prepareAiRequest>;
export type BotExecutionResult =
  | "finalized"
  | "retry"
  | "cancelled"
  | "unconfirmed";
export type BotExecutionDependencies = {
  allowedModels: ReadonlySet<string>;
  context: () => Promise<BotContext | null>;
  prepare: (
    context: BotContext,
    request: PreparedRequest | null,
  ) => Promise<string>;
  generate: (request: PreparedRequest) => Promise<AiReply>;
  settle: (
    usage: AiUsage | null,
    rejected: boolean,
    responseId?: string,
  ) => Promise<boolean>;
  complete: (decision: Decision) => Promise<boolean>;
  retry: (delaySeconds?: number) => Promise<boolean>;
  cancel: () => Promise<boolean>;
};
const handoff = (reason: string): Decision => ({
  action: "handoff",
  text: "",
  reason,
  knowledge_ids: [],
});

async function acknowledge(write: () => Promise<boolean>): Promise<boolean> {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      if (await write()) return true;
    } catch { /* Retry persistence only. */ }
  }
  return false;
}

export async function executeBotReply(
  deps: BotExecutionDependencies,
): Promise<BotExecutionResult> {
  let context: BotContext | null;
  try {
    context = await deps.context();
  } catch {
    return "unconfirmed";
  }
  if (!context) {
    return await acknowledge(deps.cancel) ? "cancelled" : "unconfirmed";
  }
  let decision: Decision | null = localBotDecision(context);
  let request: PreparedRequest | null = null;
  if (!decision) {
    try {
      request = prepareAiRequest(context, deps.allowedModels);
    } catch (error) {
      decision = handoff(
        error instanceof AiReplyError ? error.code : "ai_configuration_invalid",
      );
    }
  }
  let prepared: string;
  try {
    prepared = await deps.prepare(context, request);
  } catch {
    // The model was never called. If reservation committed before its reply was
    // lost, it can be settled at zero before retrying the job.
    await acknowledge(() => deps.settle(null, true));
    return await acknowledge(deps.retry) ? "retry" : "unconfirmed";
  }
  if (prepared === "stale") {
    return await acknowledge(deps.retry) ? "retry" : "unconfirmed";
  }
  if (prepared === "already_prepared") return "unconfirmed";
  if (prepared === "quota_pending") {
    if (await acknowledge(deps.retry)) return "retry";
    decision = handoff("ai_budget_unavailable");
  } else if (prepared === "quota_exhausted") {
    decision = handoff("ai_budget_exhausted");
  } else if (prepared === "window_closed") {
    decision = handoff("customer_service_window_closed");
  } else if (prepared !== "prepared") return "unconfirmed";

  if (!decision && request) {
    let reply: AiReply;
    try {
      reply = await deps.generate(request);
    } catch (error) {
      const failure = error instanceof AiReplyError
        ? error
        : new AiReplyError("ai_generation_unknown");
      if (
        !await acknowledge(() => deps.settle(failure.usage, failure.rejected))
      ) return "unconfirmed";
      if (
        failure.retryable &&
        await acknowledge(() => deps.retry(failure.retryAfterSeconds))
      ) return "retry";
      decision = handoff(
        failure.retryable ? "ai_retry_exhausted" : failure.code,
      );
      return await acknowledge(() => deps.complete(decision!))
        ? "finalized"
        : "unconfirmed";
    }
    if (
      !await acknowledge(() =>
        deps.settle(reply.usage, false, reply.responseId)
      )
    ) return "unconfirmed";
    decision = reply.decision;
  }
  if (!decision) return "unconfirmed";
  return await acknowledge(() => deps.complete(decision!))
    ? "finalized"
    : "unconfirmed";
}
