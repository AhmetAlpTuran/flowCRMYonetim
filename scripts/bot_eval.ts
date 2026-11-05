/**
 * Industry pack conversation check against a real model (costs a few cents).
 *
 *   docker run --rm -e OPENAI_API_KEY -e EVAL_MODEL=gpt-4o-mini -e EVAL_REPEAT=3 \
 *     -v "<repo>:/app" -w /app denoland/deno:2.9.8 \
 *     deno run --allow-env --allow-net=api.openai.com scripts/bot_eval.ts
 *
 * Every case runs EVAL_REPEAT times (default 1); a case passes only if every run passes.
 * The catalog, bookings and leads are in memory: nothing touches a database or WhatsApp.
 */
import { EVAL_CASES, runEvalCase } from "../supabase/functions/_shared/bot_eval.ts";
import { istanbulToday } from "../supabase/functions/_shared/bot_tools.ts";

const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim() ?? "";
if (!apiKey) {
  console.error("Set OPENAI_API_KEY to run the bot evaluation.");
  Deno.exit(2);
}
const model = Deno.env.get("EVAL_MODEL")?.trim() || "gpt-4o-mini";
const repeat = Math.min(Math.max(Number(Deno.env.get("EVAL_REPEAT") ?? "1") || 1, 1), 10);
const today = istanbulToday();

let passedCases = 0;
let tokens = 0;
for (const evalCase of EVAL_CASES) {
  const runs = [];
  for (let i = 0; i < repeat; i++) {
    runs.push(await runEvalCase(evalCase, { apiKey, model, today }));
  }
  tokens += runs.reduce((sum, r) => sum + r.tokens, 0);
  const passed = runs.filter((r) => r.passed).length;
  if (passed === repeat) passedCases++;
  console.log(`${passed === repeat ? "PASS" : "FAIL"} ${passed}/${repeat}  ${evalCase.name}`);
  for (const run of runs.filter((r) => !r.passed)) {
    console.log(`       ${run.action}/${run.reason} tools=[${run.calls.join(", ")}] ${run.failures.join("; ")}`);
    console.log(`       "${run.text.replace(/\s+/g, " ").slice(0, 200)}"`);
  }
}
console.log(`\n${passedCases}/${EVAL_CASES.length} cases passed with ${model} (${repeat} run(s) each, ${tokens} tokens).`);
Deno.exit(passedCases === EVAL_CASES.length ? 0 : 1);
