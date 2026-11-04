import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ApiError } from "./http.ts";
import { inboxMessagePayload } from "./inbox_payload.ts";
import { GraphApiError, WhatsAppApi } from "./whatsapp_api.ts";

Deno.test("text replies keep the existing payload shape", () => {
  assertEquals(inboxMessagePayload("905551112233", "Merhaba", "id:lease"), {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: "905551112233",
    biz_opaque_callback_data: "id:lease",
    type: "text",
    text: { body: "Merhaba", preview_url: false },
  });
});

Deno.test("media replies send the uploaded ID and caption, never the placeholder", () => {
  const image = inboxMessagePayload("905551112233", "[Fotoğraf]", "c", {
    kind: "image",
    mediaId: "777",
    caption: "  Aracın ön tarafı ",
  });
  assertEquals(image.type, "image");
  assertEquals(image.image, { id: "777", caption: "Aracın ön tarafı" });
  assertEquals("text" in image, false);

  const bare = inboxMessagePayload("905551112233", "[Fotoğraf]", "c", {
    kind: "image",
    mediaId: "778",
    caption: null,
  });
  assertEquals(bare.image, { id: "778" });

  const document = inboxMessagePayload("905551112233", "[Belge: teklif.pdf]", "c", {
    kind: "document",
    mediaId: "779",
    fileName: "teklif.pdf",
  });
  assertEquals(document.document, { id: "779", filename: "teklif.pdf" });
});

Deno.test("media upload posts multipart to the phone number and returns the ID", async () => {
  let seen: { url: string; init?: RequestInit } | undefined;
  const api = new WhatsAppApi("v23.0", "fixture-token-never-real", (input, init) => {
    seen = { url: String(input), init };
    return Promise.resolve(new Response(JSON.stringify({ id: "123456" })));
  });
  const id = await api.uploadMedia("900000000002", {
    bytes: new Uint8Array([1, 2, 3]),
    mimeType: "application/pdf",
    fileName: "teklif.pdf",
  });
  assertEquals(id, "123456");
  assertEquals(seen?.url, "https://graph.facebook.com/v23.0/900000000002/media");
  const form = seen?.init?.body as FormData;
  assertEquals(form.get("messaging_product"), "whatsapp");
  assertEquals(form.get("type"), "application/pdf");
  assertEquals((form.get("file") as File).name, "teklif.pdf");
  assertEquals(
    (seen?.init?.headers as Record<string, string>).Authorization,
    "Bearer fixture-token-never-real",
  );
});

Deno.test("media upload rejects provider errors and malformed IDs", async () => {
  const reply = (body: unknown, status = 200): typeof fetch => () =>
    Promise.resolve(new Response(JSON.stringify(body), { status }));
  const file = { bytes: new Uint8Array([1]), mimeType: "image/png", fileName: "a.png" };
  await assertRejects(
    () => new WhatsAppApi("v23.0", "t", reply({ error: { code: 100 } }, 400)).uploadMedia("1", file),
    GraphApiError,
  );
  await assertRejects(
    () => new WhatsAppApi("v23.0", "t", reply({ id: "../x" })).uploadMedia("1", file),
    ApiError,
  );
  await assertRejects(
    () => new WhatsAppApi("v23.0", "t", reply({ id: "1" })).uploadMedia("abc", file),
    ApiError,
  );
});
