// Authored only. Uses local signed fixtures, never provider/network calls.
import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ApiError, readBytes } from "./http.ts";
import { normalizeWhatsAppEvents } from "./whatsapp_events.ts";
import { webhookHandler } from "./whatsapp_webhook.ts";
import { verifyWebhook } from "./webhook_signature.ts";

Deno.test("a stalled request body is cancelled at its deadline", async () => {
  let cancelled = false;
  const stream = new ReadableStream<Uint8Array>({
    cancel() {
      cancelled = true;
    },
  });
  const request = new Request("https://fixture.invalid", {
    method: "POST",
    body: stream,
  });
  await assertRejects(() => readBytes(request, 100, 5), ApiError, "timed out");
  assertEquals(cancelled, true);
});

const secret = "fixture-app-secret-never-real";
const verifyToken = "fixture-webhook-token-with-at-least-32-characters";
const encode = (value: unknown) =>
  new Uint8Array(new TextEncoder().encode(JSON.stringify(value)));
const status = {
  id: "wamid.fixture-status",
  recipient_id: "905550000001",
  timestamp: "1700000000",
  status: "delivered",
  errors: [{ code: 100, message: "private detail that must be omitted" }],
};
function entry(
  waba = "123",
  phone = "456",
  statuses: unknown[] = [status],
  messages: unknown[] = [],
) {
  return {
    id: waba,
    changes: [{
      field: "messages",
      value: {
        messaging_product: "whatsapp",
        metadata: { phone_number_id: phone },
        statuses,
        messages,
      },
    }],
  };
}
async function signed(body: Uint8Array<ArrayBuffer>, signingSecret = secret) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(signingSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = [
    ...new Uint8Array(await crypto.subtle.sign("HMAC", key, body)),
  ].map((n) => n.toString(16).padStart(2, "0")).join("");
  return new Request("https://fixture.invalid/webhook", {
    method: "POST",
    body,
    headers: {
      "X-Hub-Signature-256": `sha256=${signature}`,
      "Content-Type": "application/json",
    },
  });
}

Deno.test("signature verifies exact bytes and rejects missing, altered or other-app signatures", async () => {
  const bytes = encode({ object: "whatsapp_business_account", entry: [] });
  assertEquals(await verifyWebhook(await signed(bytes), secret), bytes);
  await assertRejects(
    () =>
      verifyWebhook(
        new Request("https://fixture.invalid", { method: "POST", body: bytes }),
        secret,
      ),
    ApiError,
  );
  await assertRejects(
    async () => verifyWebhook(await signed(bytes, "wrong-secret"), secret),
    ApiError,
  );
  const original = await signed(bytes);
  await assertRejects(
    () =>
      verifyWebhook(
        new Request(original.url, {
          method: "POST",
          headers: original.headers,
          body: new TextEncoder().encode(
            JSON.stringify(
              JSON.parse(new TextDecoder().decode(bytes)),
              null,
              2,
            ),
          ),
        }),
        secret,
      ),
    ApiError,
  );
});

Deno.test("receiver does not persist unsigned data and acknowledges only after durable storage", async () => {
  let writes = 0;
  const handler = webhookHandler({
    appSecret: () => secret,
    verifyToken: () => verifyToken,
    ingest: () => {
      writes++;
      return Promise.reject(
        new ApiError(503, "fixture_storage_unavailable", "Unavailable"),
      );
    },
  });
  const bytes = encode({
    object: "whatsapp_business_account",
    tenant_id: "caller-cannot-route",
    entry: [entry()],
  });
  assertEquals(
    (await handler(await signed(bytes, "wrong-secret"))).status,
    401,
  );
  assertEquals(writes, 0);
  assertEquals((await handler(await signed(bytes))).status, 503);
  assertEquals(writes, 1);
});

Deno.test("subscription verification returns plain challenge and never ingests events", async () => {
  const handler = webhookHandler({
    appSecret: () => secret,
    verifyToken: () => verifyToken,
    ingest: () => {
      throw new Error("GET cannot ingest");
    },
  });
  const url = new URL("https://fixture.invalid");
  url.searchParams.set("hub.mode", "subscribe");
  url.searchParams.set("hub.verify_token", verifyToken);
  url.searchParams.set("hub.challenge", "123456");
  const response = await handler(new Request(url));
  assertEquals(response.status, 200);
  assertEquals(await response.text(), "123456");
  url.searchParams.set("hub.verify_token", "wrong");
  assertEquals((await handler(new Request(url))).status, 403);
});

Deno.test("all entries and changes are normalized without trusting caller tenant fields", async () => {
  const inbound = {
    id: "wamid.inbound",
    from: "905550000002",
    timestamp: "1700000001",
    type: "text",
    text: { body: "Hello" },
  };
  const first = entry("123", "456", [status], [inbound]);
  first.changes.push(
    entry("123", "457", [{ ...status, id: "wamid.second" }]).changes[0],
  );
  const events = await normalizeWhatsAppEvents(
    encode({
      object: "whatsapp_business_account",
      tenant_id: "ignored",
      entry: [first, entry("999", "888")],
    }),
  );
  assertEquals(events.length, 4);
  assertEquals(events.map((event) => event.phone_number_id), [
    "456",
    "456",
    "457",
    "888",
  ]);
  assertEquals(events[1].payload.error_code, "meta_100");
  assertEquals(JSON.stringify(events).includes("private detail"), false);
  assertEquals(JSON.stringify(events).includes("tenant_id"), false);
  const replay = await normalizeWhatsAppEvents(
    encode({ object: "whatsapp_business_account", entry: [first] }),
  );
  assertEquals(replay[0].event_key, events[0].event_key);
  assertEquals(events[1].event_key === events[3].event_key, false);
});

Deno.test("invalid IDs, timestamps and oversized bodies are rejected before processing", async () => {
  for (
    const change of [{ id: "invalid" }, { timestamp: "NaN" }, {
      recipient_id: "not-a-number",
    }]
  ) {
    await assertRejects(
      () =>
        normalizeWhatsAppEvents(
          encode({
            object: "whatsapp_business_account",
            entry: [entry("123", "456", [{ ...status, ...change }])],
          }),
        ),
      ApiError,
    );
  }
  const oversized = new Uint8Array(2 * 1024 * 1024 + 1);
  await assertRejects(
    async () => verifyWebhook(await signed(oversized), secret),
    ApiError,
  );
});
