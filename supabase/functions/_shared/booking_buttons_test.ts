import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  bookingButtons,
  buttonReplyText,
  parseButtonTap,
  parsePeriod,
  trackHolds,
} from "./bot_tools.ts";
import { inboxMessagePayload } from "./inbox_payload.ts";

const ID = "22222222-2222-4222-8222-222222222222";
const OTHER = "33333333-3333-4333-8333-333333333333";

Deno.test("buttons appear only for exactly one fresh hold", () => {
  assertEquals(bookingButtons([ID, ID]), [
    { id: `booking:confirm:${ID}`, title: "Onayla" },
    { id: `booking:cancel:${ID}`, title: "İptal" },
  ]);
  assertEquals(bookingButtons([]), undefined);
  assertEquals(bookingButtons([ID, OTHER]), undefined);
  assertEquals(bookingButtons(["not-a-uuid"]), undefined);
});

Deno.test("taps are read only from well-formed button replies", () => {
  const tap = (id: unknown) => ({ type: "interactive", interactive: { type: "button_reply", button_reply: { id, title: "Onayla" } } });
  assertEquals(parseButtonTap(tap(`booking:confirm:${ID}`)), { action: "confirm", bookingId: ID });
  assertEquals(parseButtonTap(tap(`booking:cancel:${ID.toUpperCase()}`)), { action: "cancel", bookingId: ID });
  for (const bad of [tap("booking:delete:" + ID), tap("confirm"), tap(42), { interactive: {} }, null]) {
    assertEquals(parseButtonTap(bad), null);
  }
});

Deno.test("tap replies are fixed Turkish texts with Istanbul dates", () => {
  const confirm = { action: "confirm" as const, bookingId: ID };
  assertEquals(
    buttonReplyText(confirm, { status: "confirmed" }, {
      name: "Deniz Odası",
      start: "2026-11-21T11:00:00.000Z",
      end: "2026-11-23T08:00:00.000Z",
    }),
    "Rezervasyonunuz onaylandı: Deniz Odası (21.11.2026 – 23.11.2026). Teşekkür ederiz!",
  );
  assertEquals(
    buttonReplyText(confirm, { error: "hold_expired_or_cancelled" }),
    "Bu ön rezervasyonun süresi dolmuş. Tarihler hâlâ uygunsa yeniden ayırmamı ister misiniz?",
  );
  assertEquals(
    buttonReplyText({ action: "cancel", bookingId: ID }, { status: "cancelled" }),
    "Ön rezervasyonunuz iptal edildi. Başka bir tarih için yardımcı olabilirim.",
  );
  assertEquals(buttonReplyText(confirm, { error: "unavailable" }).includes("temsilcimiz"), true);
});

Deno.test("periods parse and holds are tracked per reply", async () => {
  assertEquals(parsePeriod('["2026-11-21 11:00:00+00","2026-11-23 08:00:00+00")'), {
    start: "2026-11-21T11:00:00.000Z",
    end: "2026-11-23T08:00:00.000Z",
  });
  assertEquals(parsePeriod("garbage"), null);
  const { runner, held } = trackHolds((call) =>
    Promise.resolve(call.name === "hold_booking" ? { booking_id: ID, status: "hold" } : { booking_id: ID, status: "confirmed" })
  );
  await runner({ call_id: "1", name: "hold_booking", arguments: "{}" });
  assertEquals(held(), [ID]);
  await runner({ call_id: "2", name: "confirm_booking", arguments: "{}" });
  assertEquals(held(), []);
});

Deno.test("button messages use the interactive format with safe fallbacks", () => {
  const buttons = bookingButtons([ID])!;
  const payload = inboxMessagePayload("905551112233", "Deniz Odası 21-23 Kasım, toplam 5.000 ₺. Onaylıyor musunuz?", "cb", undefined, buttons);
  assertEquals(payload.type, "interactive");
  assertEquals(payload.interactive, {
    type: "button",
    body: { text: "Deniz Odası 21-23 Kasım, toplam 5.000 ₺. Onaylıyor musunuz?" },
    action: {
      buttons: [
        { type: "reply", reply: { id: `booking:confirm:${ID}`, title: "Onayla" } },
        { type: "reply", reply: { id: `booking:cancel:${ID}`, title: "İptal" } },
      ],
    },
  });
  assertEquals(inboxMessagePayload("905551112233", "x".repeat(1025), "cb", undefined, buttons).type, "text");
  assertEquals(
    inboxMessagePayload("905551112233", "x", "cb", undefined, [{ id: "a", title: "Bu başlık yirmi karakterden uzun" }]).type,
    "text",
  );
  assertEquals(inboxMessagePayload("905551112233", "x", "cb").type, "text");
});
