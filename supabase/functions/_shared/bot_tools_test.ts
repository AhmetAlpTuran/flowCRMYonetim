import {
  assert,
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  AiReplyError,
  type BotContext,
  generateAiReply,
  localBotDecision,
  MAX_TOOL_ROUNDS,
  prepareAiRequest,
} from "./ai_reply.ts";
import {
  catalogToolDefinitions,
  type CatalogType,
  createToolRunner,
  istanbulToday,
  periodFor,
  type ToolDatabase,
} from "./bot_tools.ts";

const types: CatalogType[] = [
  {
    key: "room",
    name: "Oda",
    kind: "bookable",
    booking_unit: "night",
    fields: [{ key: "beds", label: "Yatak", type: "number" }],
  },
  {
    key: "vehicle",
    name: "Araç",
    kind: "listing",
    booking_unit: null,
    fields: [{ key: "gear", label: "Vites", type: "select", options: ["Manuel", "Otomatik"] }],
  },
];
const ROOM = "11111111-1111-4111-8111-111111111111";
const BOOKING = "22222222-2222-4222-8222-222222222222";

Deno.test("tool definitions follow strict schema rules and depend on the catalog", () => {
  const all = catalogToolDefinitions(types);
  const names = all.map((t) => t.name);
  assertEquals(names, [
    "search_catalog",
    "create_lead",
    "check_availability",
    "hold_booking",
    "confirm_booking",
    "cancel_booking",
    "my_bookings",
  ]);
  for (const definition of all) {
    const parameters = definition.parameters as Record<string, unknown>;
    assertEquals(definition.strict, true);
    assertEquals(parameters.additionalProperties, false);
    assertEquals(
      (parameters.required as string[]).sort(),
      Object.keys(parameters.properties as object).sort(),
      `${definition.name} must require every property`,
    );
  }
  assert(String(all[0].description).includes("gear (Vites, select: Manuel/Otomatik)"));
  assertEquals(
    catalogToolDefinitions([types[1]]).map((t) => t.name),
    ["search_catalog", "create_lead"],
    "listing-only catalogs get no booking tools",
  );
  assertEquals(catalogToolDefinitions([]), []);
});

Deno.test("dates become Istanbul check-in/out and hourly ranges", () => {
  assertEquals(periodFor("night", { check_in_date: "2026-11-21", check_out_date: "2026-11-23" }), {
    start: "2026-11-21T11:00:00.000Z",
    end: "2026-11-23T08:00:00.000Z",
  });
  assertEquals(periodFor("hour", { date: "2026-11-21", start_time: "09:30", hours: 2 }), {
    start: "2026-11-21T06:30:00.000Z",
    end: "2026-11-21T08:30:00.000Z",
  });
  assertEquals(periodFor("day", { check_in_date: "2026-11-21", check_out_date: "2026-11-21" }), {
    start: "2026-11-20T21:00:00.000Z",
    end: "2026-11-21T21:00:00.000Z",
  });
  for (
    const bad of [
      { check_in_date: "2026-11-23", check_out_date: "2026-11-21" },
      { check_in_date: "21.11.2026", check_out_date: "2026-11-23" },
    ]
  ) {
    let failed = false;
    try {
      periodFor("night", bad);
    } catch {
      failed = true;
    }
    assert(failed);
  }
  assertEquals(istanbulToday(new Date("2026-11-05T22:30:00Z")), "2026-11-06 (Cuma)");
});

function fakeDb(responses: Record<string, { data?: unknown; error?: { code: string } }>) {
  const calls: { name: string; params: Record<string, unknown> }[] = [];
  const db: ToolDatabase = {
    rpc: (name, params) => {
      calls.push({ name, params });
      const r = responses[name] ?? { data: { ok: true } };
      return Promise.resolve({ data: r.data ?? null, error: r.error ?? null });
    },
    resourceUnit: (id) => Promise.resolve(id === ROOM ? "night" : null),
    conversationBookings: () => Promise.resolve([{ id: BOOKING, status: "hold" }]),
  };
  return { db, calls };
}
const scope = { tenantId: "t-1", conversationId: "c-1", jobId: "j-1" };
const call = (name: string, args: unknown) => ({ call_id: "call_1", name, arguments: JSON.stringify(args) });

Deno.test("tools call the scoped functions and never take a phone from the model", async () => {
  const { db, calls } = fakeDb({});
  const run = createToolRunner(db, scope);
  await run(call("search_catalog", {
    type_key: "vehicle",
    query: null,
    filters: [{ field: "gear", equals: "Otomatik", min: null, max: null }, {
      field: "year",
      equals: null,
      min: 2020,
      max: null,
    }],
    price_min: null,
    price_max: 1200000,
  }));
  assertEquals(calls[0].name, "bot_search_resources");
  assertEquals(calls[0].params.p_filters, {
    gear: "Otomatik",
    year: { min: 2020, max: null },
    price: { min: null, max: 1200000 },
  });

  const holdArgs = {
    resource_id: ROOM,
    check_in_date: "2026-11-21",
    check_out_date: "2026-11-23",
    date: null,
    start_time: null,
    hours: null,
    customer_name: "Ayşe",
    customer_phone: "905000000000",
  };
  await run(call("hold_booking", holdArgs));
  await run(call("hold_booking", { ...holdArgs, customer_name: "Ayşe Y." }));
  const holds = calls.filter((c) => c.name === "bot_create_booking_hold");
  assertEquals(holds[0].params.p_conversation_id, "c-1");
  assertEquals(holds[0].params.p_start, "2026-11-21T11:00:00.000Z");
  assertEquals("p_customer_phone" in holds[0].params, false);
  assertEquals(holds[0].params.p_request_key, holds[1].params.p_request_key, "same dates => same hold");
  assert(String(holds[0].params.p_request_key).startsWith("j-1:hold_booking:"));

  await run(call("hold_booking", { ...holdArgs, check_out_date: "2026-11-24" }));
  assertNotEquals(
    calls.at(-1)!.params.p_request_key,
    holds[0].params.p_request_key,
    "different dates => different hold",
  );

  await run(call("confirm_booking", { booking_id: BOOKING }));
  assertEquals(calls.at(-1)!.params, {
    p_tenant_id: "t-1",
    p_conversation_id: "c-1",
    p_booking_id: BOOKING,
    p_status: "confirmed",
  });
  assertEquals(await run(call("my_bookings", {})), { bookings: [{ id: BOOKING, status: "hold" }] });

  await run(call("create_lead", {
    kind: "test_drive",
    resource_id: null,
    note: "Cumartesi",
    preferred_date: "2026-11-21",
    preferred_time: "14:00",
    customer_name: null,
  }));
  assertEquals(calls.at(-1)!.params.p_preferred_at, "2026-11-21T14:00:00+03:00");
  assertEquals(calls.at(-1)!.params.p_details, { note: "Cumartesi" });
});

Deno.test("tool failures become results the model can explain", async () => {
  const { db, calls } = fakeDb({ bot_create_booking_hold: { error: { code: "P0015" } } });
  const run = createToolRunner(db, scope);
  assertEquals(
    await run(call("hold_booking", {
      resource_id: ROOM,
      check_in_date: "2026-11-21",
      check_out_date: "2026-11-22",
      date: null,
      start_time: null,
      hours: null,
      customer_name: null,
    })),
    { error: "not_available" },
  );
  assertEquals(await run(call("check_availability", { resource_id: "not-a-uuid" })), {
    error: "invalid_input",
    message: "resource_id is not a valid id",
  });
  assertEquals(
    await run(call("check_availability", {
      resource_id: "33333333-3333-4333-8333-333333333333",
      check_in_date: "2026-11-21",
      check_out_date: "2026-11-22",
    })),
    { error: "not_found" },
  );
  assertEquals((await run({ call_id: "x", name: "search_catalog", arguments: "{broken" }) as { error: string }).error, "invalid_input");
  assertEquals(await run(call("delete_everything", {})), { error: "unknown_tool" });
  assertEquals((await run(call("create_lead", { kind: "spam" })) as { error: string }).error, "invalid_input");
  assertEquals(calls.length, 1);
});

// --- Tool loop --------------------------------------------------------------

const context = (): BotContext => ({
  tenant_id: "t-1",
  conversation_id: "c-1",
  input_message_id: "m-1",
  automation_revision: 1,
  context_revision: 1,
  input: { type: "text", body: "Cumartesi boş oda var mı?" },
  settings: {
    name: "Ava",
    tone: "sıcak",
    language: "Türkçe",
    system_prompt: "",
    model: "gpt-4o-mini",
    temperature: 0.3,
  },
  knowledge: [],
  history: [],
});
const toolset = { definitions: catalogToolDefinitions(types), today: "2026-11-05 (Perşembe)" };
const usage = (n: number) => ({ input_tokens: n, output_tokens: 10, total_tokens: n + 10 });
const functionCall = (id: string) => ({
  id: `resp_${id}`,
  status: "completed",
  usage: usage(100),
  output: [{
    type: "function_call",
    id: `fc_${id}`,
    call_id: `call_${id}`,
    name: "search_catalog",
    arguments: JSON.stringify({ type_key: "room", query: null, filters: [], price_min: null, price_max: null }),
    status: "completed",
  }],
});
const finalMessage = (reason: string) => ({
  id: "resp_final",
  status: "completed",
  usage: usage(200),
  output: [{
    type: "message",
    role: "assistant",
    status: "completed",
    content: [{
      type: "output_text",
      text: JSON.stringify({ action: "reply", text: "Deniz Odası müsait.", reason, knowledge_ids: [] }),
    }],
  }],
});
function sequence(...bodies: unknown[]) {
  const sent: Record<string, unknown>[] = [];
  const transport: typeof fetch = (_url, init) => {
    sent.push(JSON.parse(String(init?.body)));
    return Promise.resolve(new Response(JSON.stringify(bodies[sent.length - 1])));
  };
  return { transport, sent };
}

Deno.test("a catalog-only business is not handed off for missing knowledge", () => {
  assertEquals(localBotDecision(context())?.reason, "insufficient_knowledge");
  assertEquals(localBotDecision(context(), true), null);
  const prepared = prepareAiRequest(context(), new Set(["gpt-4o-mini"]), toolset);
  const payload = JSON.parse(prepared.body);
  assertEquals(payload.tools.length, 7);
  assertEquals(payload.parallel_tool_calls, false);
  assert(payload.instructions.includes("Today is 2026-11-05 (Perşembe)"));
  assert(!payload.instructions.includes("You have no tools"));
  assert(prepared.toolsEnabled);
  assert(prepared.reserveTokens > new TextEncoder().encode(prepared.body).length * MAX_TOOL_ROUNDS);
});

Deno.test("tool round trip sends results back and sums usage", async () => {
  const prepared = prepareAiRequest(context(), new Set(["gpt-4o-mini"]), toolset);
  const { transport, sent } = sequence(functionCall("a"), finalMessage("tool_answer"));
  const ran: string[] = [];
  const reply = await generateAiReply(prepared, "fixture", transport, (c) => {
    ran.push(c.name);
    return Promise.resolve([{ id: ROOM, name: "Deniz Odası" }]);
  });
  assertEquals(ran, ["search_catalog"]);
  assertEquals(reply.decision.reason, "tool_answer");
  assertEquals(reply.usage, { input_tokens: 300, output_tokens: 20, total_tokens: 320 });
  const second = sent[1].input as Record<string, unknown>[];
  const echoed = second.find((item) => item.type === "function_call")!;
  assertEquals(echoed.call_id, "call_a");
  assertEquals("id" in echoed, false, "stored item ids are not sent back with store=false");
  const output = second.find((item) => item.type === "function_call_output")!;
  assertEquals(JSON.parse(String(output.output))[0].name, "Deniz Odası");
});

Deno.test("tool answers require tools, rounds are bounded and usage survives failures", async () => {
  const plain = prepareAiRequest({ ...context(), knowledge: [{ id: "kb-1", title: "t", content: "c" }] }, new Set(["gpt-4o-mini"]));
  await assertRejects(
    () => generateAiReply(plain, "fixture", sequence(finalMessage("tool_answer")).transport),
    AiReplyError,
  );

  const prepared = prepareAiRequest(context(), new Set(["gpt-4o-mini"]), toolset);
  const loop = sequence(...Array.from({ length: MAX_TOOL_ROUNDS + 2 }, (_, i) => functionCall(String(i))));
  const error = await assertRejects(
    () => generateAiReply(prepared, "fixture", loop.transport, () => Promise.resolve({})),
    AiReplyError,
  );
  assertEquals(error.code, "ai_tool_rounds_exceeded");
  assertEquals(error.usage?.total_tokens, 110 * (MAX_TOOL_ROUNDS + 1));

  const failing = sequence(functionCall("a"), { error: { code: "server_error" } });
  const transport: typeof fetch = (url, init) =>
    failing.sent.length === 0
      ? failing.transport(url, init)
      : Promise.resolve(new Response("{}", { status: 500 }));
  const midway = await assertRejects(
    () => generateAiReply(prepared, "fixture", transport, () => Promise.resolve({})),
    AiReplyError,
  );
  assertEquals(midway.usage?.total_tokens, 110, "first round is billed even when the second fails");

  const noRunner = await assertRejects(
    () => generateAiReply(prepared, "fixture", sequence(functionCall("a")).transport),
    AiReplyError,
  );
  assertEquals(noRunner.code, "ai_response_invalid");
});
