import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { confirmCheckout } from "./billing_checkout.ts";
import { billingUrls, callbackUrl, paymentPageUrl, resultPageUrl } from "./billing_urls.ts";
import {
  authorizationHeader,
  checkoutRequest,
  initializeCheckout,
  type IyzicoConfig,
  iyzicoConfig,
  IyzicoError,
  iyzicoRequest,
  retrieveCheckout,
  upgradeSubscription,
  verifyWebhookSignature,
  webhookEvent,
} from "./iyzico.ts";

const config: IyzicoConfig = {
  apiKey: "sandbox-api-key",
  secretKey: "sandbox-secret",
  baseUrl: "https://sandbox-api.iyzipay.com",
  merchantId: "123456",
};
const customer = {
  name: "Ayşe",
  surname: "Yılmaz",
  email: "a@example.com",
  gsm_number: "+905551112233",
  identity_number: "12345678901",
  contact_name: "Ayşe Yılmaz",
  address: "Bağdat Cd. 1",
  city: "İstanbul",
  country: "Turkey",
  zip_code: null,
};

type Call = { url: string; init: RequestInit };
function fake(responses: (Response | Error)[]): { transport: typeof fetch; calls: Call[] } {
  const calls: Call[] = [];
  const transport = (async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(url), init: init ?? {} });
    const next = responses.shift();
    if (!next) throw new Error("unexpected call");
    if (next instanceof Error) throw next;
    return next;
  }) as typeof fetch;
  return { transport, calls };
}
const ok = (body: Record<string, unknown>) => new Response(JSON.stringify({ status: "success", ...body }));

Deno.test("IYZWSv2 header matches the documented algorithm (Python vector)", async () => {
  assertEquals(
    await authorizationHeader(config.apiKey, config.secretKey, "/v2/subscription/checkoutform/initialize",
      '{"locale":"tr"}', "1700000000000abcdef"),
    "IYZWSv2 YXBpS2V5OnNhbmRib3gtYXBpLWtleSZyYW5kb21LZXk6MTcwMDAwMDAwMDAwMGFiY2RlZiZzaWduYXR1cmU6YTc5ZjY5MDllYjJlZGYyYmZlMzk2MjdiNmZlMTU2OTcxMGU4N2I4OGU1ZGNlNTU4NGMxMzE1MWNjYTFkMTRkMQ==",
  );
  // GET requests sign only randomKey + path.
  const header = await authorizationHeader(config.apiKey, config.secretKey, "/v2/subscription/checkoutform/tok-1", "",
    "1700000000000abcdef");
  assert(atob(header.slice(8)).endsWith("3b8575ded6c1c32e9e61290aa6034be7dbd125ff9c9c9081e1a8ef42f419fd08"));
});

Deno.test("requests carry the signature headers and map provider failures", async () => {
  const { transport, calls } = fake([ok({ value: 1 })]);
  assertEquals((await iyzicoRequest(config, "POST", "/v2/x", { a: 1 }, transport)).value, 1);
  const headers = calls[0].init.headers as Record<string, string>;
  assert(headers["Authorization"].startsWith("IYZWSv2 "));
  assert(atob(headers["Authorization"].slice(8)).includes(`randomKey:${headers["x-iyzi-rnd"]}&`));
  assertEquals(calls[0].url, "https://sandbox-api.iyzipay.com/v2/x");
  assertEquals(calls[0].init.body, '{"a":1}');

  const rejected = fake([new Response(JSON.stringify({ status: "failure", errorCode: "100001" }), { status: 400 })]);
  const error = await assertRejects(() => iyzicoRequest(config, "POST", "/v2/x", {}, rejected.transport), IyzicoError);
  assertEquals([error.code, error.providerCode], ["provider_rejected", "100001"]);
  const down = fake([new Response("busy", { status: 502 })]);
  assertEquals(
    (await assertRejects(() => iyzicoRequest(config, "GET", "/v2/x", null, down.transport), IyzicoError)).code,
    "provider_unavailable",
  );
  const offline = fake([new TypeError("network")]);
  assertEquals(
    (await assertRejects(() => iyzicoRequest(config, "GET", "/v2/x", null, offline.transport), IyzicoError)).code,
    "provider_unavailable",
  );
});

Deno.test("checkout form request and response follow the subscription API", async () => {
  const request = checkoutRequest({
    checkoutId: "c-1",
    pricingPlanCode: "PRO-M",
    callbackUrl: "https://x/cb",
    customer,
  });
  assertEquals(request.pricingPlanReferenceCode, "PRO-M");
  assertEquals(request.subscriptionInitialStatus, "ACTIVE");
  assertEquals(request.conversationId, "c-1");
  const sent = request.customer as Record<string, unknown>;
  assertEquals(sent.gsmNumber, "+905551112233");
  assertEquals(sent.billingAddress, { contactName: "Ayşe Yılmaz", city: "İstanbul", country: "Turkey", address: "Bağdat Cd. 1" });

  const { transport, calls } = fake([ok({ token: "tok-1", checkoutFormContent: "<script>x</script>", tokenExpireTime: 1200 })]);
  assertEquals(await initializeCheckout(config, { checkoutId: "c-1", pricingPlanCode: "PRO-M", callbackUrl: "https://x/cb", customer }, transport),
    { token: "tok-1", content: "<script>x</script>", expiresIn: 1200 });
  assertEquals(new URL(calls[0].url).pathname, "/v2/subscription/checkoutform/initialize");
  const empty = fake([ok({})]);
  await assertRejects(() => initializeCheckout(config, { checkoutId: "c", pricingPlanCode: "P", callbackUrl: "u", customer }, empty.transport), IyzicoError);
});

Deno.test("checkout results are read from iyzico, never from the browser", async () => {
  const active = fake([ok({ data: { referenceCode: "SUB-1", customerReferenceCode: "CUS-1", subscriptionStatus: "ACTIVE" } })]);
  assertEquals(await retrieveCheckout(config, "tok-1", active.transport), { active: true, subscriptionRef: "SUB-1", customerRef: "CUS-1" });
  assertEquals(active.calls[0].init.method, "GET");
  assertEquals(new URL(active.calls[0].url).pathname, "/v2/subscription/checkoutform/tok-1");
  const pending = fake([ok({ data: { referenceCode: "SUB-2", subscriptionStatus: "PENDING" } })]);
  assertEquals((await retrieveCheckout(config, "tok-2", pending.transport)).active, false);
  await assertRejects(() => retrieveCheckout(config, "../evil", fake([]).transport), IyzicoError);

  const upgrade = fake([ok({})]);
  await upgradeSubscription(config, "SUB-1", "BIZ-M", upgrade.transport);
  assertEquals(new URL(upgrade.calls[0].url).pathname, "/v2/subscription/subscriptions/SUB-1/upgrade");
  assertEquals(JSON.parse(String(upgrade.calls[0].init.body)).upgradePeriod, "NOW");
});

Deno.test("confirmCheckout completes with iyzico's answer and the stored token", async () => {
  const calls: Record<string, unknown>[] = [];
  const rpc = async (name: string, params: Record<string, unknown>) => {
    calls.push({ name, ...params });
    return { data: "completed", error: null };
  };
  const active = fake([ok({ data: { referenceCode: "SUB-1", customerReferenceCode: "CUS-1", subscriptionStatus: "ACTIVE" } })]);
  assertEquals(await confirmCheckout(rpc, config, "c-1", "tok-1", active.transport), "completed");
  assertEquals(calls[0], {
    name: "complete_billing_checkout",
    p_checkout_id: "c-1",
    p_token: "tok-1",
    p_success: true,
    p_subscription_ref: "SUB-1",
    p_customer_ref: "CUS-1",
    p_failure_code: null,
  });
  await assertRejects(() => confirmCheckout(rpc, config, "c-1", "tok-1", fake([new TypeError("x")]).transport), IyzicoError);
});

Deno.test("webhooks: V3 subscription signature (Python vector) and event mapping", async () => {
  const payload = {
    orderReferenceCode: "ORD-1",
    customerReferenceCode: "CUS-1",
    subscriptionReferenceCode: "SUB-1",
    iyziReferenceCode: "IYZ-1",
    iyziEventType: "subscription.order.success",
    iyziEventTime: 1700000000000,
  };
  const good = "7e71eb88308719dcb49c2f64325c22e7faabb3a795c9f4d74da2ad4c7b564213";
  assert(await verifyWebhookSignature(config, payload, good));
  assert(await verifyWebhookSignature(config, payload, good.toUpperCase()));
  assert(!await verifyWebhookSignature(config, { ...payload, subscriptionReferenceCode: "SUB-2" }, good));
  assert(!await verifyWebhookSignature(config, payload, null));
  assert(!await verifyWebhookSignature(config, payload, "nope"));
  assertEquals(webhookEvent(payload), { kind: "renewed", eventKey: "subscription.order.success:ORD-1", subscriptionRef: "SUB-1" });
  assertEquals(webhookEvent({ ...payload, iyziEventType: "subscription.order.failure" })?.kind, "payment_failed");
  assertEquals(webhookEvent({ ...payload, iyziEventType: "payment.success" }), null);
  assertEquals(webhookEvent({ iyziEventType: "subscription.order.success" }), null);
});

Deno.test("configuration and public URLs", () => {
  const env = (values: Record<string, string>) => (name: string) => values[name];
  assertEquals(iyzicoConfig(env({ IYZICO_API_KEY: "k", IYZICO_SECRET_KEY: "s" })), null, "merchant ID required");
  assertEquals(iyzicoConfig(env({ IYZICO_API_KEY: "k", IYZICO_SECRET_KEY: "s", IYZICO_MERCHANT_ID: "1" }))?.baseUrl,
    "https://sandbox-api.iyzipay.com");
  const urls = billingUrls(env({ SUPABASE_URL: "https://ref.supabase.co", BILLING_PAGE_URL: "https://a.github.io/app/odeme" }))!;
  assertEquals(urls.functions, "https://ref.supabase.co/functions/v1");
  assertEquals(paymentPageUrl(urls, "c-1"), "https://a.github.io/app/odeme/?oturum=c-1");
  assertEquals(resultPageUrl(urls, "basarili"), "https://a.github.io/app/odeme/sonuc/?durum=basarili");
  assertEquals(callbackUrl(urls, "c-1"), "https://ref.supabase.co/functions/v1/iyzico-gateway/callback/c-1");
  assertEquals(billingUrls(env({ SUPABASE_URL: "https://ref.supabase.co" })), null, "payment page required");
});
