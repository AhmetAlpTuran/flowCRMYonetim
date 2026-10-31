import { ApiError } from "./http.ts";
import { requiredEnv } from "./supabase.ts";

import { secretEquals } from "./secret_compare.ts";

export async function requireWorker(
  req: Request,
  secretName = "CAMPAIGN_WORKER_SECRET",
): Promise<void> {
  const configured = requiredEnv(secretName);
  if (configured.length < 32 || configured.length > 256) {
    throw new ApiError(
      503,
      "worker_secret_invalid",
      "Worker authentication is not configured",
    );
  }
  const presented = req.headers.get("Authorization")?.match(
    /^Bearer (\S{1,256})$/i,
  )?.[1];
  if (!presented || !await secretEquals(presented, configured)) {
    throw new ApiError(401, "unauthorized", "Worker authentication required");
  }
}
