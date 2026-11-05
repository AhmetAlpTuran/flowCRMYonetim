import { ApiError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { requireWorker } from "../_shared/worker_auth.ts";

// Queue health for uptime monitors: 200 when every background queue is moving, 503 with
// the list of problems otherwise (stuck queues, unconfirmed send outcomes, unmatched
// billing events). GET or POST with `Authorization: Bearer <HEALTH_CHECK_SECRET>`.
Deno.serve(async (req) => {
  if (req.method !== "GET" && req.method !== "POST") {
    return jsonResponse({ code: "method_not_allowed", error: "Method not allowed" }, 405);
  }
  try {
    await requireWorker(req, "HEALTH_CHECK_SECRET");
    const { data, error } = await serviceClient().rpc("ops_health", {});
    if (error || !data || typeof data !== "object") {
      throw new ApiError(503, "health_unavailable", "Health report unavailable");
    }
    const report = data as { healthy?: boolean };
    return jsonResponse(report, report.healthy ? 200 : 503);
  } catch (error) {
    return errorResponse(error);
  }
});
