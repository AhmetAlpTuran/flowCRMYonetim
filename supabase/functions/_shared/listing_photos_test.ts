import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { catalogToolDefinitions, createToolRunner, MAX_REPLY_PHOTOS, trackPhotos } from "./bot_tools.ts";
import { inboxMessagePayload } from "./inbox_payload.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const CAR = "22222222-2222-4222-8222-222222222222";
const BARE = "33333333-3333-4333-8333-333333333333";
const photo = (n: number) => `${TENANT}/${CAR}/0000000${n}-0000-4000-8000-000000000000.jpg`;

function runner() {
  return createToolRunner({
    rpc: async () => ({ data: null, error: null }),
    resourceUnit: async () => null,
    conversationBookings: async () => [],
    resourcePhotos: async (id) =>
      id === CAR
        ? { name: "2019 Fiat Egea", photos: [photo(1), photo(2), photo(3), photo(4)] }
        : id === BARE
        ? { name: "Clio", photos: [] }
        : null,
  }, { tenantId: TENANT, conversationId: "c", jobId: "j" });
}

Deno.test("send_photos is offered with any catalog", () => {
  const names = catalogToolDefinitions([{ key: "vehicle", name: "Araç", kind: "listing", booking_unit: null, fields: [] }])
    .map((d) => d.name);
  assertEquals(names.includes("send_photos"), true);
});

Deno.test("photos are collected for the reply, capped, and paths never reach the model", async () => {
  const tracked = trackPhotos(runner());
  const first = await tracked.runner({ call_id: "1", name: "send_photos", arguments: JSON.stringify({ resource_id: CAR }) });
  assertEquals(first, { status: "queued", name: "2019 Fiat Egea", photo_count: 4, sent: MAX_REPLY_PHOTOS });
  assertEquals(tracked.photos(), [
    { path: photo(1), caption: "2019 Fiat Egea" },
    { path: photo(2), caption: null },
    { path: photo(3), caption: null },
  ]);
  // A second request in the same reply finds no room left.
  const again = await tracked.runner({ call_id: "2", name: "send_photos", arguments: JSON.stringify({ resource_id: CAR }) });
  assertEquals((again as Record<string, unknown>).note, "photo_limit_reached");
  assertEquals(tracked.photos().length, MAX_REPLY_PHOTOS);
  assertEquals(await tracked.runner({ call_id: "3", name: "send_photos", arguments: JSON.stringify({ resource_id: BARE }) }),
    { error: "no_photos" });
  assertEquals(await tracked.runner({ call_id: "4", name: "send_photos", arguments: JSON.stringify({ resource_id: TENANT }) }),
    { error: "not_found" });
  assertEquals(await tracked.runner({ call_id: "5", name: "send_photos", arguments: '{"resource_id":"../x"}' }),
    { error: "invalid_input", message: "resource_id is not a valid id" });
});

Deno.test("a listing photo is sent as an image with its caption", () => {
  assertEquals(
    inboxMessagePayload("905551112233", "2019 Fiat Egea", "cb", { kind: "image", mediaId: "123", caption: "2019 Fiat Egea" }),
    {
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: "905551112233",
      biz_opaque_callback_data: "cb",
      type: "image",
      image: { id: "123", caption: "2019 Fiat Egea" },
    },
  );
});
