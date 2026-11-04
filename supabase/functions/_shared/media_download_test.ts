import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ApiError } from "./http.ts";
import {
  downloadWhatsAppMedia,
  isMetaMediaUrl,
  mediaExtension,
  MediaTooLargeError,
} from "./media_download.ts";
import { GraphApiError, WhatsAppApi } from "./whatsapp_api.ts";

const token = "fixture-tenant-token-never-a-real-secret";
const mediaUrl = "https://lookaside.fbsbx.com/whatsapp_business/attachments/?mid=1&ext=1";

function fixture(
  metadata: Record<string, unknown>,
  body: Uint8Array | null,
  calls: { url: string; auth: string | null }[],
  status = 200,
): typeof fetch {
  return (input, init) => {
    const url = String(input);
    calls.push({
      url,
      auth: new Headers(init?.headers).get("Authorization"),
    });
    if (url.startsWith("https://graph.facebook.com/")) {
      return Promise.resolve(new Response(JSON.stringify(metadata)));
    }
    return Promise.resolve(new Response(body, { status }));
  };
}

Deno.test("media URLs must be Meta HTTPS hosts", () => {
  assert(isMetaMediaUrl(mediaUrl));
  assert(isMetaMediaUrl("https://mmg.whatsapp.net/v/t62/abc"));
  for (
    const bad of [
      "http://lookaside.fbsbx.com/x",
      "https://evil.example/x",
      "https://lookaside.fbsbx.com.evil.example/x",
      "https://user:pass@lookaside.fbsbx.com/x",
      "not a url",
      42,
    ]
  ) {
    assertEquals(isMetaMediaUrl(bad), false, String(bad));
  }
});

Deno.test("download resolves the ID, sends the token only to Meta and returns bytes", async () => {
  const calls: { url: string; auth: string | null }[] = [];
  const bytes = new Uint8Array([1, 2, 3, 4]);
  const transport = fixture(
    { url: mediaUrl, mime_type: "image/jpeg; codecs=x", file_size: 4, id: "123" },
    bytes,
    calls,
  );
  const api = new WhatsAppApi("v23.0", token, transport);
  const media = await downloadWhatsAppMedia(api, "123", transport);
  assertEquals(Array.from(media.bytes), [1, 2, 3, 4]);
  assertEquals(media.mimeType, "image/jpeg");
  assertEquals(calls.length, 2);
  assertEquals(new URL(calls[0].url).pathname, "/v23.0/123");
  assertEquals(calls[1].url, mediaUrl);
  for (const call of calls) assertEquals(call.auth, `Bearer ${token}`);
});

Deno.test("download refuses foreign hosts, oversize and truncated media", async () => {
  const calls: { url: string; auth: string | null }[] = [];
  const foreign = fixture({ url: "https://evil.example/x", file_size: 1 }, new Uint8Array([1]), calls);
  await assertRejects(
    () => downloadWhatsAppMedia(new WhatsAppApi("v23.0", token, foreign), "1", foreign),
    ApiError,
  );
  assertEquals(calls.filter((c) => c.url.includes("evil")).length, 0);

  const declaredLarge = fixture({ url: mediaUrl, file_size: 11 }, new Uint8Array(11), []);
  await assertRejects(
    () => downloadWhatsAppMedia(new WhatsAppApi("v23.0", token, declaredLarge), "1", declaredLarge, 10),
    MediaTooLargeError,
  );

  const streamedLarge = fixture({ url: mediaUrl }, new Uint8Array(11), []);
  await assertRejects(
    () => downloadWhatsAppMedia(new WhatsAppApi("v23.0", token, streamedLarge), "1", streamedLarge, 10),
    MediaTooLargeError,
  );

  const truncated = fixture({ url: mediaUrl, file_size: 5 }, new Uint8Array(3), []);
  await assertRejects(
    () => downloadWhatsAppMedia(new WhatsAppApi("v23.0", token, truncated), "1", truncated),
    ApiError,
    "incomplete",
  );

  const expired = fixture({ url: mediaUrl }, null, [], 404);
  await assertRejects(
    () => downloadWhatsAppMedia(new WhatsAppApi("v23.0", token, expired), "1", expired),
    GraphApiError,
  );

  await assertRejects(
    () => downloadWhatsAppMedia(new WhatsAppApi("v23.0", token, expired), "../me", expired),
    ApiError,
  );
});

Deno.test("stored file extensions follow the MIME type", () => {
  assertEquals(mediaExtension("image/jpeg"), "jpg");
  assertEquals(mediaExtension("audio/ogg; codecs=opus"), "ogg");
  assertEquals(mediaExtension("application/pdf"), "pdf");
  assertEquals(mediaExtension("application/x-unknown"), "bin");
});
