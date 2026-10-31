import { ApiError, errorResponse, jsonResponse } from "./http.ts";
import { secretEquals } from "./secret_compare.ts";
import { requiredEnv, serviceClient } from "./supabase.ts";
import { verifyWebhook } from "./webhook_signature.ts";
import {
  normalizeWhatsAppEvents,
  type WhatsAppEvent,
} from "./whatsapp_events.ts";

type Dependencies = {
  appSecret: () => string;
  verifyToken: () => string;
  ingest: (events: WhatsAppEvent[]) => Promise<void>;
};
export function webhookHandler(deps: Dependencies) {
  return async (req: Request): Promise<Response> => {
    try {
      if (req.method === "GET") {
        const url = new URL(req.url);
        const configured = deps.verifyToken();
        if (configured.length < 32 || configured.length > 256) {
          throw new ApiError(
            503,
            "webhook_configuration",
            "Webhook unavailable",
          );
        }
        const token = url.searchParams.get("hub.verify_token") ?? "";
        const challenge = url.searchParams.get("hub.challenge") ?? "";
        if (
          url.searchParams.get("hub.mode") !== "subscribe" ||
          token.length > 256 || !challenge || challenge.length > 256 ||
          !await secretEquals(token, configured)
        ) {
          throw new ApiError(
            403,
            "webhook_verification_failed",
            "Verification failed",
          );
        }
        return new Response(challenge, {
          headers: {
            "Content-Type": "text/plain; charset=utf-8",
            "Cache-Control": "no-store",
          },
        });
      }
      if (req.method !== "POST") {
        return jsonResponse({ error: "Method not allowed" }, 405);
      }
      const bytes = await verifyWebhook(req, deps.appSecret());
      const events = await normalizeWhatsAppEvents(bytes);
      if (events.length) await deps.ingest(events);
      // Only durable commit earns 200. Lost replies are harmless on provider retry.
      return jsonResponse({ status: "received" });
    } catch (error) {
      return errorResponse(error);
    }
  };
}

export const handleWhatsAppWebhook = webhookHandler({
  appSecret: () => requiredEnv("META_APP_SECRET"),
  verifyToken: () => requiredEnv("WHATSAPP_WEBHOOK_TOKEN"),
  ingest: async (events) => {
    const { error } = await serviceClient().rpc("ingest_whatsapp_events", {
      p_events: events,
    });
    if (error) {
      throw new ApiError(
        503,
        "webhook_storage_unavailable",
        "Webhook storage unavailable; retry delivery",
      );
    }
  },
});
