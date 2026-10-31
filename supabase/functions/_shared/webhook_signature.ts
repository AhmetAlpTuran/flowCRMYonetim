import { ApiError, readBytes } from "./http.ts";

export async function verifyWebhook(
  req: Request,
  appSecret: string,
): Promise<Uint8Array<ArrayBuffer>> {
  const signature = req.headers.get("X-Hub-Signature-256");
  if (!signature || !/^sha256=[0-9a-f]{64}$/i.test(signature)) {
    throw new ApiError(
      401,
      "invalid_webhook_signature",
      "Invalid webhook signature",
    );
  }
  if (!appSecret) {
    throw new ApiError(503, "webhook_configuration", "Webhook unavailable");
  }
  const bytes = await readBytes(req, 2 * 1024 * 1024);
  const supplied = Uint8Array.from(
    signature.slice(7).match(/../g)!,
    (pair) => parseInt(pair, 16),
  );
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(appSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  if (!await crypto.subtle.verify("HMAC", key, supplied, bytes)) {
    throw new ApiError(
      401,
      "invalid_webhook_signature",
      "Invalid webhook signature",
    );
  }
  return bytes;
}
