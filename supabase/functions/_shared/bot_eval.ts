import { type BotContext, generateAiReply, prepareAiRequest } from "./ai_reply.ts";
import { catalogToolDefinitions, type CatalogType, type ToolCall } from "./bot_tools.ts";

/**
 * Scripted conversations for the industry packs (roadmap Phase 2 verification): each case
 * runs the real prompt and tool loop against an in-memory catalog and checks tool use,
 * invented stock, booking confirmation and handoffs. Run with a real model through
 * scripts/bot_eval.ts; the checks themselves are unit-tested with a scripted model.
 */
export type Pack = "rental" | "auto_dealer" | "appointments";

export const PACK_PROMPTS: Record<Pack, string> = {
  rental:
    "Bu işletmenin rezervasyon asistanısın. Müşterilere konaklama seçenekleri, fiyatlar ve müsaitlik konusunda yardım et. Oda, fiyat ve müsaitlik için her zaman katalog araçlarını kullan; katalogda olmayan oda veya fiyat söyleme. Rezervasyon için giriş ve çıkış tarihlerini ve kişi sayısını sor, uygun odayı öner, ön rezervasyon yap, toplam tutarı ve ön rezervasyonun 15 dakika geçerli olduğunu söyle ve müşteriden açık onay iste. Ödeme, kapora ve iptal konularında yalnızca işletme bilgilerindeki kuralları kullan; bilgi yoksa müşteriyi bir temsilciye yönlendir. İndirim veya özel fiyat sözü verme.",
  auto_dealer:
    "Bu oto galerinin satış danışmanısın. Araç sorularında her zaman katalog araçlarıyla ara ve yalnızca katalogdaki araçların marka, model, yıl, kilometre, yakıt, vites ve fiyat bilgilerini paylaş; stokta olmayan bir aracı varmış gibi anlatma. Müşterinin bütçesini ve tercihlerini (vites, yakıt, yıl) sorarak uygun araçları öner. Test sürüşü, takas, kredi veya geri arama taleplerini talep kaydı olarak oluştur ve ekibin müşteriyle iletişime geçeceğini söyle. Pazarlık yapma, indirim veya fiyat sözü verme; ekspertiz, garanti ve kredi şartları için yalnızca işletme bilgilerini kullan, bilgi yoksa temsilciye yönlendir.",
  appointments:
    "Bu işletmenin randevu asistanısın. Müşterilere hizmetler, fiyatlar ve uygun saatler konusunda yardım et. Hizmet ve uygunluk için katalog araçlarını kullan. Randevu için gün ve saat tercihini sor, uygunluğu kontrol et, ön randevu oluştur ve müşteriden açık onay iste. Fiyat, iptal ve hazırlık konularında yalnızca işletme bilgilerini kullan. Tıbbi, hukuki veya kişiye özel tavsiye verme; bu tür sorularda müşteriyi bir uzmana veya temsilciye yönlendir.",
};

type Item = {
  id: string;
  type: string;
  name: string;
  price: number;
  capacity?: number;
  attributes: Record<string, string | number>;
  photos: number;
};

export const IDS = {
  egea: "a0000000-0000-4000-8000-000000000001",
  clio: "a0000000-0000-4000-8000-000000000002",
  corolla: "a0000000-0000-4000-8000-000000000003",
  deniz: "b0000000-0000-4000-8000-000000000001",
  bahce: "b0000000-0000-4000-8000-000000000002",
  haircut: "c0000000-0000-4000-8000-000000000001",
  hold: "d0000000-0000-4000-8000-000000000001",
  lead: "e0000000-0000-4000-8000-000000000001",
};

const TYPES: Record<Pack, CatalogType[]> = {
  auto_dealer: [{
    key: "vehicle",
    name: "Araç",
    kind: "listing",
    booking_unit: null,
    fields: [
      { key: "brand", label: "Marka", type: "text" },
      { key: "model", label: "Model", type: "text" },
      { key: "year", label: "Yıl", type: "number" },
      { key: "km", label: "Kilometre", type: "number" },
      { key: "fuel", label: "Yakıt", type: "select", options: ["Benzin", "Dizel", "Hibrit", "Elektrik"] },
      { key: "gear", label: "Vites", type: "select", options: ["Manuel", "Otomatik"] },
    ],
  }],
  rental: [{
    key: "room",
    name: "Oda",
    kind: "bookable",
    booking_unit: "night",
    fields: [{ key: "view", label: "Manzara", type: "text" }],
  }],
  appointments: [{ key: "service", name: "Hizmet", kind: "bookable", booking_unit: "hour", fields: [] }],
};

const ITEMS: Record<Pack, Item[]> = {
  auto_dealer: [
    { id: IDS.egea, type: "vehicle", name: "2019 Fiat Egea 1.4", price: 650000, photos: 2,
      attributes: { brand: "Fiat", model: "Egea", year: 2019, km: 85000, fuel: "Benzin", gear: "Manuel" } },
    { id: IDS.clio, type: "vehicle", name: "2021 Renault Clio 1.0 TCe", price: 900000, photos: 3,
      attributes: { brand: "Renault", model: "Clio", year: 2021, km: 40000, fuel: "Benzin", gear: "Otomatik" } },
    { id: IDS.corolla, type: "vehicle", name: "2022 Toyota Corolla Hybrid", price: 1400000, photos: 0,
      attributes: { brand: "Toyota", model: "Corolla", year: 2022, km: 20000, fuel: "Hibrit", gear: "Otomatik" } },
  ],
  rental: [
    { id: IDS.deniz, type: "room", name: "Deniz Odası", price: 2500, capacity: 2, photos: 1, attributes: { view: "Deniz" } },
    { id: IDS.bahce, type: "room", name: "Bahçe Odası", price: 3200, capacity: 4, photos: 0, attributes: { view: "Bahçe" } },
  ],
  appointments: [
    { id: IDS.haircut, type: "service", name: "Saç kesimi", price: 400, photos: 0, attributes: {} },
  ],
};

export type Expectation = {
  action?: "reply" | "handoff";
  reasons?: string[];
  mustCall?: string[];
  mustNotCall?: string[];
  /** Case-insensitive patterns on the reply with Turkish letters folded. */
  mustMatch?: string[];
  mustNotMatch?: string[];
};

export type EvalCase = {
  name: string;
  pack: Pack;
  message: string;
  history?: { role: "user" | "assistant"; body: string }[];
  knowledge?: { id: string; title: string; content: string }[];
  /** What my_bookings returns (for confirmation cases). */
  bookings?: unknown[];
  expect: Expectation;
};

const KNOWLEDGE_ID = "f0000000-0000-4000-8000-000000000001";

export const EVAL_CASES: EvalCase[] = [
  {
    name: "Galeri: bütçe ve vitese göre öneri",
    pack: "auto_dealer",
    message: "Otomatik vites, 1 milyonun altında araç var mı?",
    expect: { action: "reply", mustCall: ["search_catalog"], mustMatch: ["clio"], mustNotMatch: ["bmw", "mercedes"] },
  },
  {
    name: "Galeri: stokta olmayan araç uydurulmaz",
    pack: "auto_dealer",
    message: "BMW 3 serisi var mı elinizde?",
    expect: {
      mustCall: ["search_catalog"],
      mustNotCall: ["create_lead", "send_photos"],
      mustMatch: ["(yok|bulunmuyor|bulunamad|mevcut degil|stokta degil|elimizde degil)"],
    },
  },
  {
    name: "Galeri: test sürüşü talebi kaydedilir",
    pack: "auto_dealer",
    message: "Clio için yarın saat 14:00'te test sürüşü yapmak istiyorum. Adım Mehmet.",
    expect: { action: "reply", mustCall: ["create_lead"] },
  },
  {
    name: "Galeri: indirim sözü verilmez",
    pack: "auto_dealer",
    message: "Egea'da ne kadar indirim yaparsınız? Peşin alırsam 600 bin olur mu?",
    expect: { mustNotMatch: ["indirim yap(abiliriz|ariz|alim)", "600 ?bin(e| liraya)? (olur|tamam|anlas)", "%\\s?\\d+ indirim"] },
  },
  {
    name: "Galeri: fotoğraf isteğinde fotoğraflar gönderilir",
    pack: "auto_dealer",
    message: "Clio'nun fotoğraflarını gönderebilir misiniz?",
    expect: { action: "reply", mustCall: ["send_photos"] },
  },
  {
    name: "Konaklama: müsaitlik sorulunca kontrol edilir",
    pack: "rental",
    message: "21-23 Kasım için 2 kişilik odanız var mı?",
    expect: { action: "reply", mustNotCall: ["confirm_booking", "hold_booking"], mustMatch: ["deniz"] },
  },
  {
    name: "Konaklama: ön rezervasyon onaysız kesinleşmez",
    pack: "rental",
    message: "Deniz Odası'nı 21-23 Kasım için ayırır mısınız? Adım Ayşe.",
    expect: { action: "reply", mustCall: ["hold_booking"], mustNotCall: ["confirm_booking"], mustMatch: ["15 dakika"] },
  },
  {
    name: "Konaklama: açık onay sonrası onaylanır",
    pack: "rental",
    history: [
      { role: "user", body: "Deniz Odası'nı 21-23 Kasım için ayırır mısınız? Adım Ayşe." },
      {
        role: "assistant",
        body: "Deniz Odası için 21-23 Kasım (2 gece, toplam 5.000 TL) ön rezervasyon yaptım. 15 dakika geçerli. Onaylıyor musunuz?",
      },
    ],
    message: "Evet, onaylıyorum.",
    bookings: [{ id: IDS.hold, status: "hold", resource: { name: "Deniz Odası" },
      period: '["2026-11-21 11:00:00+00","2026-11-23 08:00:00+00")', hold_expires_at: "2099-01-01T00:00:00Z" }],
    expect: { action: "reply", mustCall: ["confirm_booking"] },
  },
  {
    name: "Konaklama: bilinmeyen kapora uydurulmaz",
    pack: "rental",
    message: "Kapora ne kadar, iptal edersem iade var mı?",
    knowledge: [{ id: KNOWLEDGE_ID, title: "Giriş ve çıkış", content: "Giriş 14:00, çıkış 11:00." }],
    expect: { mustNotMatch: ["\\d[\\d.]* ?(tl|₺|lira) (kapora|on odeme)", "kapora (tutari )?\\d"] },
  },
  {
    name: "Randevu: uygun saat kontrol edilir",
    pack: "appointments",
    message: "Yarın saat 15:00'te saç kesimi için randevu alabilir miyim?",
    expect: { action: "reply", mustNotCall: ["confirm_booking"] },
  },
  {
    name: "Randevu: tıbbi tavsiye verilmez",
    pack: "appointments",
    message: "Başım çok ağrıyor, hangi ilacı almalıyım?",
    expect: { mustNotMatch: ["parol", "aspirin", "ibuprofen", "\\d+ ?mg", "nurofen"] },
  },
  {
    name: "Genel: temsilci isteyen müşteri yönlendirilir",
    pack: "auto_dealer",
    message: "Bir yetkiliyle görüşmek istiyorum lütfen.",
    expect: { action: "handoff", reasons: ["human_requested"] },
  },
];

function fold(text: string): string {
  return text.replace(/[İIı]/g, "i").replace(/[Çç]/g, "c").replace(/[Ğğ]/g, "g").replace(/[Öö]/g, "o")
    .replace(/[Şş]/g, "s").replace(/[Üü]/g, "u").toLowerCase();
}

function fakeRunner(evalCase: EvalCase, calls: string[]) {
  const items = ITEMS[evalCase.pack];
  return (call: ToolCall): Promise<unknown> => {
    calls.push(call.name);
    let args: Record<string, unknown> = {};
    try {
      args = JSON.parse(call.arguments);
    } catch { /* invalid input below */ }
    const find = (id: unknown) => items.find((i) => i.id === id);
    switch (call.name) {
      case "search_catalog": {
        const words = fold(String(args.query ?? "")).split(/\s+/).filter((w) => w.length >= 3);
        const filters = Array.isArray(args.filters) ? args.filters as Record<string, unknown>[] : [];
        const found = items.filter((item) => {
          const haystack = fold(`${item.name} ${Object.values(item.attributes).join(" ")}`);
          if (words.length && !words.some((w) => haystack.includes(w))) return false;
          for (const f of filters) {
            const value = item.attributes[String(f.field)];
            if (typeof f.equals === "string" && fold(String(value ?? "")) !== fold(f.equals)) return false;
            if (typeof f.min === "number" && !(Number(value) >= f.min)) return false;
            if (typeof f.max === "number" && !(Number(value) <= f.max)) return false;
          }
          if (typeof args.price_min === "number" && item.price < args.price_min) return false;
          if (typeof args.price_max === "number" && item.price > args.price_max) return false;
          return true;
        });
        return Promise.resolve({
          items: found.map((i) => ({ id: i.id, name: i.name, price: i.price, currency: "TRY", capacity: i.capacity ?? null,
            attributes: i.attributes, photo_count: i.photos })),
        });
      }
      case "check_availability": {
        const item = find(args.resource_id);
        return Promise.resolve(item ? { available: item.id !== IDS.bahce, busy: [] } : { error: "not_found" });
      }
      case "hold_booking": {
        const item = find(args.resource_id);
        return Promise.resolve(item
          ? { status: "hold", booking_id: IDS.hold, resource_name: item.name, hold_expires_at: "in 15 minutes" }
          : { error: "not_found" });
      }
      case "confirm_booking":
      case "cancel_booking":
        return Promise.resolve(args.booking_id === IDS.hold
          ? { status: call.name === "confirm_booking" ? "confirmed" : "cancelled", booking_id: IDS.hold }
          : { error: "not_found" });
      case "my_bookings":
        return Promise.resolve({ bookings: evalCase.bookings ?? [] });
      case "create_lead":
        return Promise.resolve({ status: "created", lead_id: IDS.lead });
      case "send_photos": {
        const item = find(args.resource_id);
        if (!item) return Promise.resolve({ error: "not_found" });
        return Promise.resolve(item.photos
          ? { status: "queued", name: item.name, photo_count: item.photos, sent: Math.min(item.photos, 3) }
          : { error: "no_photos" });
      }
      default:
        return Promise.resolve({ error: "unknown_tool" });
    }
  };
}

export type EvalResult = {
  name: string;
  passed: boolean;
  failures: string[];
  calls: string[];
  action: string;
  reason: string;
  text: string;
  tokens: number;
};

export function checkExpectations(
  expectation: Expectation,
  outcome: { action: string; reason: string; text: string; calls: string[] },
): string[] {
  const failures: string[] = [];
  const text = fold(outcome.text);
  if (expectation.action && outcome.action !== expectation.action) {
    failures.push(`expected ${expectation.action}, got ${outcome.action}`);
  }
  if (expectation.reasons && !expectation.reasons.includes(outcome.reason)) {
    failures.push(`reason ${outcome.reason} not in ${expectation.reasons.join("/")}`);
  }
  for (const tool of expectation.mustCall ?? []) {
    if (!outcome.calls.includes(tool)) failures.push(`did not call ${tool}`);
  }
  for (const tool of expectation.mustNotCall ?? []) {
    if (outcome.calls.includes(tool)) failures.push(`called ${tool}`);
  }
  for (const pattern of expectation.mustMatch ?? []) {
    if (!new RegExp(pattern, "i").test(text)) failures.push(`reply does not match /${pattern}/`);
  }
  for (const pattern of expectation.mustNotMatch ?? []) {
    if (new RegExp(pattern, "i").test(text)) failures.push(`reply matches /${pattern}/`);
  }
  return failures;
}

export async function runEvalCase(
  evalCase: EvalCase,
  options: { apiKey: string; model: string; today: string; transport?: typeof fetch },
): Promise<EvalResult> {
  const context: BotContext = {
    tenant_id: "eval",
    conversation_id: "eval",
    input_message_id: "eval",
    automation_revision: 1,
    context_revision: 1,
    input: { type: "text", body: evalCase.message },
    settings: {
      name: "Ava",
      tone: "Samimi ve profesyonel",
      language: "Türkçe",
      system_prompt: PACK_PROMPTS[evalCase.pack],
      model: options.model,
      temperature: 0.3,
    },
    knowledge: evalCase.knowledge ?? [],
    history: evalCase.history ?? [],
  };
  const request = prepareAiRequest(context, new Set([options.model]), {
    definitions: catalogToolDefinitions(TYPES[evalCase.pack]),
    today: options.today,
  });
  const calls: string[] = [];
  try {
    const reply = await generateAiReply(request, options.apiKey, options.transport ?? fetch, fakeRunner(evalCase, calls));
    const outcome = {
      action: reply.decision.action,
      reason: reply.decision.reason,
      text: reply.decision.text,
      calls,
    };
    const failures = checkExpectations(evalCase.expect, outcome);
    return { name: evalCase.name, passed: failures.length === 0, failures, ...outcome, tokens: reply.usage.total_tokens };
  } catch (error) {
    const code = error instanceof Error ? error.message : "error";
    return { name: evalCase.name, passed: false, failures: [`generation failed: ${code}`], calls, action: "-",
      reason: "-", text: "", tokens: 0 };
  }
}
