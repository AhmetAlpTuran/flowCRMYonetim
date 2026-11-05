import { secretEquals } from "./secret_compare.ts";

/**
 * iyzico subscription API (https://docs.iyzico.com): IYZWSv2 request signing, the
 * subscription checkout form, cancel/upgrade, and V3 webhook signatures.
 */
export type IyzicoConfig = {
  apiKey: string;
  secretKey: string;
  baseUrl: string;
  merchantId: string;
};

export const IYZICO_SANDBOX_URL = "https://sandbox-api.iyzipay.com";

/** Null when iyzico is not configured; online payment is then unavailable. */
export function iyzicoConfig(read: (name: string) => string | undefined = (n) => Deno.env.get(n)): IyzicoConfig | null {
  const apiKey = read("IYZICO_API_KEY")?.trim() ?? "";
  const secretKey = read("IYZICO_SECRET_KEY")?.trim() ?? "";
  const merchantId = read("IYZICO_MERCHANT_ID")?.trim() ?? "";
  const baseUrl = (read("IYZICO_BASE_URL")?.trim() || IYZICO_SANDBOX_URL).replace(/\/+$/, "");
  if (!apiKey || !secretKey || !merchantId || !/^https?:\/\/[^\s/]+/.test(baseUrl)) return null;
  return { apiKey, secretKey, baseUrl, merchantId };
}

export class IyzicoError extends Error {
  constructor(readonly code: "provider_rejected" | "provider_unavailable", readonly providerCode?: string) {
    super(code);
  }
}

const encoder = new TextEncoder();

async function hmacHex(key: string, message: string): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey("raw", encoder.encode(key), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
  ]);
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, encoder.encode(message)));
  return Array.from(signature, (b) => b.toString(16).padStart(2, "0")).join("");
}

function base64(text: string): string {
  let binary = "";
  for (const byte of encoder.encode(text)) binary += String.fromCharCode(byte);
  return btoa(binary);
}

/** `IYZWSv2 base64(apiKey:..&randomKey:..&signature:hex(HMAC-SHA256(randomKey + path + body)))`. */
export async function authorizationHeader(
  apiKey: string,
  secretKey: string,
  path: string,
  body: string,
  randomKey: string,
): Promise<string> {
  const signature = await hmacHex(secretKey, randomKey + path + body);
  return `IYZWSv2 ${base64(`apiKey:${apiKey}&randomKey:${randomKey}&signature:${signature}`)}`;
}

function randomKey(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  return `${Date.now()}${Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("")}`;
}

export async function iyzicoRequest(
  config: IyzicoConfig,
  method: "GET" | "POST",
  path: string,
  payload: Record<string, unknown> | null,
  transport: typeof fetch = fetch,
): Promise<Record<string, unknown>> {
  const body = payload ? JSON.stringify(payload) : "";
  const rnd = randomKey();
  let response: Response;
  try {
    response = await transport(config.baseUrl + path, {
      method,
      headers: {
        "Authorization": await authorizationHeader(config.apiKey, config.secretKey, path, body, rnd),
        "x-iyzi-rnd": rnd,
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      ...(payload ? { body } : {}),
      signal: AbortSignal.timeout(20000),
    });
  } catch {
    throw new IyzicoError("provider_unavailable");
  }
  let data: Record<string, unknown>;
  try {
    data = await response.json();
  } catch {
    throw new IyzicoError(response.status >= 500 ? "provider_unavailable" : "provider_rejected");
  }
  if (response.status >= 500) throw new IyzicoError("provider_unavailable");
  if (data?.status !== "success") {
    const code = typeof data?.errorCode === "string" || typeof data?.errorCode === "number"
      ? String(data.errorCode).slice(0, 40)
      : undefined;
    throw new IyzicoError("provider_rejected", code);
  }
  return data;
}

export type CheckoutCustomer = {
  name: string;
  surname: string;
  email: string;
  gsm_number: string;
  identity_number: string;
  contact_name: string;
  address: string;
  city: string;
  country: string;
  zip_code: string | null;
};

export function checkoutRequest(input: {
  checkoutId: string;
  pricingPlanCode: string;
  callbackUrl: string;
  customer: CheckoutCustomer;
}): Record<string, unknown> {
  const c = input.customer;
  const address = {
    contactName: c.contact_name,
    city: c.city,
    country: c.country,
    address: c.address,
    ...(c.zip_code ? { zipCode: c.zip_code } : {}),
  };
  return {
    locale: "tr",
    conversationId: input.checkoutId,
    callbackUrl: input.callbackUrl,
    pricingPlanReferenceCode: input.pricingPlanCode,
    subscriptionInitialStatus: "ACTIVE",
    customer: {
      name: c.name,
      surname: c.surname,
      email: c.email,
      gsmNumber: c.gsm_number,
      identityNumber: c.identity_number,
      billingAddress: address,
      shippingAddress: address,
    },
  };
}

/** Starts a subscription checkout form; returns the token and the form's HTML/JS. */
export async function initializeCheckout(
  config: IyzicoConfig,
  input: Parameters<typeof checkoutRequest>[0],
  transport: typeof fetch = fetch,
): Promise<{ token: string; content: string; expiresIn: number }> {
  const data = await iyzicoRequest(config, "POST", "/v2/subscription/checkoutform/initialize", checkoutRequest(input), transport);
  const token = data.token;
  const content = data.checkoutFormContent;
  if (typeof token !== "string" || !token || typeof content !== "string" || !content) {
    throw new IyzicoError("provider_rejected");
  }
  const expiresIn = typeof data.tokenExpireTime === "number" ? data.tokenExpireTime : 1800;
  return { token, content, expiresIn };
}

/** The checkout result, confirmed with iyzico by token (never trusted from the browser). */
export async function retrieveCheckout(
  config: IyzicoConfig,
  token: string,
  transport: typeof fetch = fetch,
): Promise<{ active: boolean; subscriptionRef: string | null; customerRef: string | null }> {
  if (!/^[A-Za-z0-9-]{1,200}$/.test(token)) throw new IyzicoError("provider_rejected");
  const data = await iyzicoRequest(config, "GET", `/v2/subscription/checkoutform/${token}`, null, transport);
  const result = (data.data ?? {}) as Record<string, unknown>;
  const subscriptionRef = typeof result.referenceCode === "string" ? result.referenceCode : null;
  const customerRef = typeof result.customerReferenceCode === "string" ? result.customerReferenceCode : null;
  return { active: result.subscriptionStatus === "ACTIVE" && !!subscriptionRef, subscriptionRef, customerRef };
}

function referencePath(ref: string): string {
  if (!/^[A-Za-z0-9-]{1,100}$/.test(ref)) throw new IyzicoError("provider_rejected");
  return `/v2/subscription/subscriptions/${ref}`;
}

export async function cancelSubscription(config: IyzicoConfig, ref: string, transport: typeof fetch = fetch) {
  await iyzicoRequest(config, "POST", `${referencePath(ref)}/cancel`, { subscriptionReferenceCode: ref }, transport);
}

/** Changes the plan now; iyzico requires the same product and billing interval. */
export async function upgradeSubscription(
  config: IyzicoConfig,
  ref: string,
  newPlanCode: string,
  transport: typeof fetch = fetch,
) {
  await iyzicoRequest(config, "POST", `${referencePath(ref)}/upgrade`, {
    upgradePeriod: "NOW",
    newPricingPlanReferenceCode: newPlanCode,
    useTrial: false,
    resetRecurrenceCount: false,
  }, transport);
}

export type WebhookEvent = {
  kind: "renewed" | "payment_failed";
  eventKey: string;
  subscriptionRef: string;
};

/** Subscription webhook payload → event, or null for anything else. */
export function webhookEvent(payload: Record<string, unknown>): WebhookEvent | null {
  const type = payload.iyziEventType;
  const order = payload.orderReferenceCode;
  const subscription = payload.subscriptionReferenceCode;
  if (typeof order !== "string" || !order || typeof subscription !== "string" || !subscription) return null;
  const kind = type === "subscription.order.success"
    ? "renewed"
    : type === "subscription.order.failure"
    ? "payment_failed"
    : null;
  if (!kind) return null;
  return { kind, eventKey: `${type}:${order}`.slice(0, 300), subscriptionRef: subscription };
}

/**
 * X-IYZ-SIGNATURE-V3 for subscription events: hex(HMAC-SHA256(secretKey, merchantId +
 * secretKey + eventType + subscriptionReferenceCode + orderReferenceCode +
 * customerReferenceCode)), compared in constant time.
 */
export async function verifyWebhookSignature(
  config: IyzicoConfig,
  payload: Record<string, unknown>,
  header: string | null,
): Promise<boolean> {
  if (!header || !/^[0-9a-fA-F]{64}$/.test(header)) return false;
  const field = (name: string) => typeof payload[name] === "string" ? payload[name] as string : "";
  const expected = await hmacHex(
    config.secretKey,
    config.merchantId + config.secretKey + field("iyziEventType") + field("subscriptionReferenceCode") +
      field("orderReferenceCode") + field("customerReferenceCode"),
  );
  return await secretEquals(expected, header.toLowerCase());
}
