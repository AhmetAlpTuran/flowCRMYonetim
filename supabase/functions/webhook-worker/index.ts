import { ApiError, endpoint, jsonResponse } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { requireWorker } from "../_shared/worker_auth.ts";

Deno.serve(endpoint(async (req) => {
  await requireWorker(req, "WEBHOOK_WORKER_SECRET");
  const client = serviceClient();
  const [receipts, messages] = await Promise.all([
    client.rpc("process_whatsapp_receipts", { p_limit: 50 }),
    client.rpc("process_whatsapp_messages", { p_limit: 50 }),
  ]);
  if (receipts.error || messages.error) {
    throw new ApiError(
      503,
      "webhook_worker_unavailable",
      "Webhook processing unavailable",
    );
  }
  return jsonResponse({ receipts: receipts.data, messages: messages.data });
}));
