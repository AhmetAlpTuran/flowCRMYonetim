import { ApiError } from "./http.ts";
import { requiredEnv } from "./supabase.ts";

export async function secretEquals(
  left: string,
  right: string,
): Promise<boolean> {
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all(
    [left, right].map(async (value) =>
      new Uint8Array(
        await crypto.subtle.digest("SHA-256", encoder.encode(value)),
      )
    ),
  );
  let difference = 0;
  for (let index = 0; index < a.length; index++) {
    difference |= a[index] ^ b[index];
  }
  return difference === 0;
}

export async function requireWorker(req: Request): Promise<void> {
  const configured = requiredEnv("CAMPAIGN_WORKER_SECRET");
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
