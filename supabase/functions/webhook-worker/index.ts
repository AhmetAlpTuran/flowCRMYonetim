import { ApiError, endpoint, jsonResponse } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { requireWorker } from "../_shared/worker_auth.ts";

Deno.serve(endpoint(async (req) => {
  await requireWorker(req, "WEBHOOK_WORKER_SECRET");
  const { data, error } = await serviceClient().rpc(
    "process_whatsapp_receipts",
    { p_limit: 50 },
  );
  if (error) {
    throw new ApiError(
      503,
      "receipt_worker_unavailable",
      "Receipt processing unavailable",
    );
  }
  return jsonResponse(data);
}));
