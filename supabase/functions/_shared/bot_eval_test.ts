import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { checkExpectations, EVAL_CASES, IDS, runEvalCase } from "./bot_eval.ts";

const usage = { input_tokens: 100, output_tokens: 10, total_tokens: 110 };
const call = (name: string, args: unknown, n: number) => ({
  id: `resp_${n}`,
  status: "completed",
  usage,
  output: [{ type: "function_call", id: `fc_${n}`, call_id: `call_${n}`, name, arguments: JSON.stringify(args), status: "completed" }],
});
const final = (action: string, text: string, reason: string) => ({
  id: "resp_final",
  status: "completed",
  usage,
  output: [{
    type: "message",
    role: "assistant",
    status: "completed",
    content: [{ type: "output_text", text: JSON.stringify({ action, text, reason, knowledge_ids: [] }) }],
  }],
});
function scripted(...bodies: unknown[]): { transport: typeof fetch; sent: Record<string, unknown>[] } {
  const sent: Record<string, unknown>[] = [];
  const transport: typeof fetch = (_url, init) => {
    sent.push(JSON.parse(String(init?.body)));
    return Promise.resolve(new Response(JSON.stringify(bodies[sent.length - 1])));
  };
  return { transport, sent };
}
const options = (transport: typeof fetch) => ({ apiKey: "test", model: "gpt-4o-mini", today: "2026-11-05 (Perşembe)", transport });

Deno.test("every pack has cases and every case names its expectations", () => {
  const packs = new Set(EVAL_CASES.map((c) => c.pack));
  assertEquals([...packs].sort(), ["appointments", "auto_dealer", "rental"]);
  assert(EVAL_CASES.every((c) => Object.keys(c.expect).length > 0));
});

Deno.test("a well-behaved scripted model passes the stock search case", async () => {
  const evalCase = EVAL_CASES.find((c) => c.name.startsWith("Galeri: bütçe"))!;
  const { transport, sent } = scripted(
    call("search_catalog", { type_key: "vehicle", query: null, filters: [{ field: "gear", equals: "Otomatik", min: null, max: null }],
      price_min: null, price_max: 1000000 }, 1),
    final("reply", "Bütçenize uygun otomatik araç: 2021 Renault Clio (900.000 TL).", "tool_answer"),
  );
  const result = await runEvalCase(evalCase, options(transport));
  assertEquals(result.failures, []);
  assertEquals(result.calls, ["search_catalog"]);
  // The fake catalog answered with only the matching car.
  const toolOutput = (sent[1].input as Record<string, unknown>[]).find((i) => i.type === "function_call_output")!;
  const items = JSON.parse(String(toolOutput.output)).items as { id: string }[];
  assertEquals(items.map((i) => i.id), [IDS.clio]);
});

Deno.test("invented stock, skipped tools and premature confirmation are caught", async () => {
  const stock = EVAL_CASES.find((c) => c.name.startsWith("Galeri: stokta"))!;
  const lying = scripted(final("reply", "Evet, 2020 BMW 320i stoğumuzda var!", "greeting_or_clarification"));
  const result = await runEvalCase(stock, options(lying.transport));
  assert(!result.passed);
  assert(result.failures.includes("did not call search_catalog"));

  const hold = EVAL_CASES.find((c) => c.name.startsWith("Konaklama: ön rezervasyon"))!;
  const eager = scripted(
    call("hold_booking", { resource_id: IDS.deniz, check_in_date: "2026-11-21", check_out_date: "2026-11-23",
      date: null, start_time: null, hours: null, customer_name: "Ayşe" }, 1),
    call("confirm_booking", { booking_id: IDS.hold }, 2),
    final("reply", "Rezervasyonunuz onaylandı.", "tool_answer"),
  );
  const held = await runEvalCase(hold, options(eager.transport));
  assert(held.failures.includes("called confirm_booking"));
  assert(held.failures.some((f) => f.includes("15 dakika")));
});

Deno.test("pattern checks fold Turkish letters", () => {
  assertEquals(checkExpectations({ mustMatch: ["bulunmuyor"] }, { action: "reply", reason: "x", text: "BMW BULUNMUYOR", calls: [] }), []);
  assertEquals(checkExpectations({ mustNotMatch: ["parol"] }, { action: "reply", reason: "x", text: "Parol alın", calls: [] }),
    ["reply matches /parol/"]);
  assertEquals(checkExpectations({ action: "handoff", reasons: ["human_requested"] },
    { action: "reply", reason: "tool_answer", text: "", calls: [] }).length, 2);
});
