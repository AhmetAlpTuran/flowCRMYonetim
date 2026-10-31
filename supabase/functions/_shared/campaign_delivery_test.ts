// Authored for the deferred verification phase. No real provider calls.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ApiError } from "./http.ts";
import { TemplateInputError } from "./template_parameters.ts";
import {
  classifyWhatsAppResponse,
  type DeliveryOutcome,
  type DispatchDependencies,
  dispatchOnce,
} from "./campaign_delivery.ts";

const reply = (body: unknown, status = 200, headers = {}) =>
  new Response(JSON.stringify(body), { status, headers });
function fixture(overrides: Partial<DispatchDependencies> = {}) {
  const calls = {
    sends: 0,
    starts: 0,
    finishes: [] as DeliveryOutcome[],
    validation: [] as string[],
    deferrals: [] as string[],
  };
  const dependencies: DispatchDependencies = {
    prepare: async () => () => {
      calls.sends++;
      return Promise.resolve(reply({ messages: [{ id: "wamid.fixture" }] }));
    },
    start: () => {
      calls.starts++;
      return Promise.resolve(true);
    },
    finish: (value) => {
      calls.finishes.push(value);
      return Promise.resolve(true);
    },
    failValidation: (value) => {
      calls.validation.push(value);
      return Promise.resolve(true);
    },
    defer: (value) => {
      calls.deferrals.push(value);
      return Promise.resolve(true);
    },
    ...overrides,
  };
  return { calls, dependencies };
}

Deno.test("lost database acknowledgement retries persistence without another provider call", async () => {
  const { calls, dependencies } = fixture();
  dependencies.finish = (value) => {
    calls.finishes.push(value);
    if (calls.finishes.length === 1) {
      return Promise.reject(new Error("DB response lost"));
    }
    return Promise.resolve(true);
  };
  assertEquals(await dispatchOnce(dependencies), "accepted");
  assertEquals(calls.sends, 1);
  assertEquals(calls.finishes.length, 2);
  assertEquals(calls.finishes[0], calls.finishes[1]);
});

Deno.test("two lost acknowledgements leave an unconfirmed outcome without resending", async () => {
  const { calls, dependencies } = fixture({
    finish: () => Promise.reject(new Error("DB unavailable")),
  });
  assertEquals(await dispatchOnce(dependencies), "unconfirmed");
  assertEquals(calls.sends, 1);
});

Deno.test("a rejected or unconfirmed dispatch marker never sends", async () => {
  const rejected = fixture({ start: () => Promise.resolve(false) });
  assertEquals(await dispatchOnce(rejected.dependencies), "skipped");
  assertEquals(rejected.calls.sends, 0);
  const lost = fixture({
    start: () => Promise.reject(new Error("Commit response lost")),
    defer: () => Promise.resolve(false),
  });
  assertEquals(await dispatchOnce(lost.dependencies), "unconfirmed");
  assertEquals(lost.calls.sends, 0);
});

Deno.test("template validation and configuration failures do not consume a provider attempt", async () => {
  const invalid = fixture({
    prepare: () => Promise.reject(new TemplateInputError("Missing body value")),
  });
  assertEquals(await dispatchOnce(invalid.dependencies), "failed");
  assertEquals(invalid.calls.validation, ["Missing body value"]);
  assertEquals(invalid.calls.starts, 0);
  const blocked = fixture({
    prepare: () =>
      Promise.reject(
        new ApiError(409, "connection_inactive", "Reconnect account"),
      ),
  });
  assertEquals(await dispatchOnce(blocked.dependencies), "blocked");
  assertEquals(blocked.calls.deferrals, ["connection_inactive"]);
  assertEquals(blocked.calls.starts, 0);
});

Deno.test("transport failure after marker is unknown, never a safe retry", async () => {
  const { calls, dependencies } = fixture();
  dependencies.prepare = async () => () => {
    calls.sends++;
    return Promise.reject(new Error("Timeout after acceptance"));
  };
  assertEquals(await dispatchOnce(dependencies), "unknown");
  assertEquals(calls.sends, 1);
  assertEquals(calls.finishes[0].errorCode, "transport_outcome_unknown");
});

Deno.test("ambiguous or malformed provider replies cannot silently replay messages", async () => {
  const responses = [
    reply({ error: { code: 130429 } }, 503),
    reply({ error: { code: 190 } }, 200),
    reply({ messages: [] }),
    reply({ messages: [{ id: "bad-id" }] }),
    reply({ messages: [{ id: "wamid.a" }, { id: "wamid.b" }] }),
    new Response("upstream unavailable", { status: 502 }),
    reply({ error: { code: "130429" } }, 400),
  ];
  for (const response of responses) {
    assertEquals((await classifyWhatsAppResponse(response)).outcome, "unknown");
  }
});

Deno.test("explicit throttle rejection is bounded and errors never expose provider payloads", async () => {
  const throttled = await classifyWhatsAppResponse(
    reply(
      { error: { code: 130429, message: "private token or customer detail" } },
      400,
      { "Retry-After": "99999" },
    ),
  );
  assertEquals(throttled.outcome, "retry");
  assertEquals(throttled.retryAfterSeconds, 3600);
  assertEquals(throttled.detail, "WhatsApp rejected the message");
  const rejected = await classifyWhatsAppResponse(
    reply({ error: { code: 100, message: "private detail" } }, 400),
  );
  assertEquals(rejected.outcome, "failed");
  assertEquals(rejected.errorCode, "meta_100");
  const auth = await classifyWhatsAppResponse(
    reply({ error: { code: 190 } }, 401),
  );
  assertEquals(auth.authRejected, true);
});
