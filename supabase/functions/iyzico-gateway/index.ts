import { confirmCheckout } from "../_shared/billing_checkout.ts";
import { billingUrls, resultPageUrl } from "../_shared/billing_urls.ts";
import { ApiError, endpoint, jsonResponse } from "../_shared/http.ts";
import { iyzicoConfig, IyzicoError, verifyWebhookSignature, webhookEvent } from "../_shared/iyzico.ts";
import { serviceClient } from "../_shared/supabase.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

// Public endpoint for the payment flow (no user session):
//   POST /iyzico-gateway/checkout          the payment page loads the iyzico form
//   POST /iyzico-gateway/callback/{id}     iyzico returns the customer after payment
//   POST /iyzico-gateway/webhook           signed renewal / failed-payment notifications
Deno.serve(endpoint(async (req) => {
  const route = new URL(req.url).pathname.replace(/^.*\/iyzico-gateway/, "");
  const config = iyzicoConfig();
  const urls = billingUrls();
  if (!config || !urls) throw new ApiError(503, "billing_not_configured", "Online payment is not configured");
  const service = serviceClient();
  const rpc = async (name: string, params: Record<string, unknown>) => await service.rpc(name, params);

  if (route === "/checkout") {
    const body = await readSmallJson(req);
    const id = typeof body.checkout_id === "string" ? body.checkout_id : "";
    if (!UUID.test(id)) throw new ApiError(422, "invalid_checkout", "Unknown checkout");
    const { data, error } = await rpc("billing_checkout_content", { p_checkout_id: id });
    if (error) throw new ApiError(503, "billing_unavailable", "Billing is temporarily unavailable");
    return jsonResponse(data);
  }

  const callback = route.match(/^\/callback\/([0-9a-f-]{36})$/);
  if (callback && UUID.test(callback[1])) {
    // The browser arrives here: always answer with a redirect to the result page.
    let outcome: "basarili" | "basarisiz" | "beklemede" = "beklemede";
    try {
      const form = await readForm(req);
      const token = form.get("token") ?? "";
      if (/^[A-Za-z0-9-]{1,200}$/.test(token)) {
        const status = await confirmCheckout(rpc, config, callback[1], token);
        outcome = status === "completed" ? "basarili" : status === "failed" ? "basarisiz" : "beklemede";
      }
    } catch (error) {
      // iyzico unreachable or the result not saved: the app re-checks the open checkout.
      outcome = error instanceof IyzicoError && error.code === "provider_rejected" ? "basarisiz" : "beklemede";
    }
    return new Response(null, { status: 303, headers: { Location: resultPageUrl(urls, outcome) } });
  }

  if (route === "/webhook") {
    const payload = await readSmallJson(req);
    if (!await verifyWebhookSignature(config, payload, req.headers.get("x-iyz-signature-v3"))) {
      throw new ApiError(401, "invalid_signature", "Invalid signature");
    }
    const event = webhookEvent(payload);
    if (!event) return jsonResponse({ status: "ignored" });
    const { data, error } = await rpc("apply_billing_webhook", {
      p_event_key: event.eventKey,
      p_kind: event.kind,
      p_subscription_ref: event.subscriptionRef,
      p_payload: {
        iyziEventType: payload.iyziEventType,
        orderReferenceCode: payload.orderReferenceCode,
        customerReferenceCode: payload.customerReferenceCode,
        iyziEventTime: payload.iyziEventTime,
      },
    });
    // A non-2xx answer makes iyzico retry (every 15 minutes, up to 3 times).
    if (error) throw new ApiError(503, "billing_unavailable", "Billing is temporarily unavailable");
    return jsonResponse({ status: data });
  }

  throw new ApiError(404, "not_found", "Unknown route");
}));

async function readText(req: Request, limit: number): Promise<string> {
  const length = Number(req.headers.get("content-length") ?? "0");
  if (length > limit) throw new ApiError(413, "payload_too_large", "Payload too large");
  const text = await req.text();
  if (text.length > limit) throw new ApiError(413, "payload_too_large", "Payload too large");
  return text;
}

async function readSmallJson(req: Request): Promise<Record<string, unknown>> {
  try {
    const value = JSON.parse(await readText(req, 16384));
    if (value && typeof value === "object" && !Array.isArray(value)) return value as Record<string, unknown>;
  } catch (error) {
    if (error instanceof ApiError) throw error;
  }
  throw new ApiError(400, "invalid_json", "JSON object required");
}

async function readForm(req: Request): Promise<URLSearchParams> {
  return new URLSearchParams(await readText(req, 16384));
}
