import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ApiError, readJson, uuid } from "./http.ts";
import {
  GraphApiError,
  verifyConnectionToken,
  WhatsAppApi,
} from "./whatsapp_api.ts";

const reply = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), { status });
const fakeToken = "fixture-token-only-never-a-real-secret";

Deno.test("token verification requires our app and both WhatsApp permissions", async () => {
  const valid = {
    is_valid: true,
    app_id: "123",
    expires_at: Math.floor(Date.now() / 1000) + 3600,
    scopes: ["whatsapp_business_management", "whatsapp_business_messaging"],
  };
  const fixture = (data: unknown): typeof fetch => () =>
    Promise.resolve(reply({ data }));
  assert(
    await verifyConnectionToken(
      "v22.0",
      fakeToken,
      "123",
      "fixture-app-secret",
      fixture(valid),
    ),
  );
  for (
    const invalid of [
      { ...valid, app_id: "456" },
      { ...valid, is_valid: false },
      { ...valid, scopes: ["whatsapp_business_management"] },
      { ...valid, expires_at: 1 },
      { ...valid, expires_at: null },
      { ...valid, data_access_expires_at: 1 },
    ]
  ) {
    await assertRejects(() =>
      verifyConnectionToken(
        "v22.0",
        fakeToken,
        "123",
        "fixture-app-secret",
        fixture(invalid),
      ), ApiError);
  }
});

Deno.test("phone lookup verifies WABA membership and never follows provider paging hosts", async () => {
  const urls: URL[] = [];
  const transport: typeof fetch = (url) => {
    urls.push(new URL(String(url)));
    return Promise.resolve(
      urls.length === 1
        ? reply({
          data: [],
          paging: {
            next: "https://attacker.invalid/leak",
            cursors: { after: "next-page" },
          },
        })
        : reply({
          data: [{
            id: "456",
            display_phone_number: "+90 555 000 0000",
            verified_name: "Fixture",
          }],
        }),
    );
  };
  const api = new WhatsAppApi("v22.0", fakeToken, transport);
  assertEquals((await api.findPhone("123", "456")).verified_name, "Fixture");
  assertEquals(urls.map((url) => url.host), [
    "graph.facebook.com",
    "graph.facebook.com",
  ]);
  assertEquals(urls[1].searchParams.get("after"), "next-page");
  const absent = new WhatsAppApi(
    "v22.0",
    fakeToken,
    () => Promise.resolve(reply({ data: [] })),
  );
  await assertRejects(() => absent.findPhone("123", "456"), ApiError);
  await assertRejects(() => absent.request("https://attacker.invalid"));
});

Deno.test("provider errors retain codes but do not expose raw messages or secrets", async () => {
  const api = new WhatsAppApi(
    "v22.0",
    fakeToken,
    () =>
      Promise.resolve(reply({ error: { code: 190, message: fakeToken } }, 401)),
  );
  const error = await assertRejects(() => api.data("123"), GraphApiError);
  assertEquals(error.providerCode, 190);
  assert(!error.message.includes(fakeToken));
});

Deno.test("request reader enforces object JSON and byte limits; UUIDs are canonical", async () => {
  const request = (body: string) =>
    new Request("https://example.invalid", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
    });
  assertEquals(await readJson(request('{"action":"connect"}')), {
    action: "connect",
  });
  await assertRejects(() => readJson(request("[]")), ApiError);
  await assertRejects(() => readJson(request("not-json")), ApiError);
  await assertRejects(
    () => readJson(request('{"data":"too long"}'), 5),
    ApiError,
  );
  assertEquals(
    uuid("ABCDEFAB-1234-1234-1234-123456789ABC", "Tenant"),
    "abcdefab-1234-1234-1234-123456789abc",
  );
});
