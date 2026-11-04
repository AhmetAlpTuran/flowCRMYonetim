import {
  assert,
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ApiError } from "./http.ts";
import {
  templateMedia,
  templateSubmission,
  uploadSessionPath,
} from "./template_submission.ts";
import { GraphApiError, WhatsAppApi } from "./whatsapp_api.ts";

const fakeToken = "fixture-tenant-token-never-a-real-secret";
const body = [{ type: "BODY", text: "Merhaba {{1}}" }];
const valid = {
  name: "kampanya_yaz",
  language: "tr",
  category: "MARKETING",
  components: body,
};

Deno.test("template submissions are validated before any provider call", () => {
  assertEquals(templateSubmission(valid), valid as unknown);
  assertEquals(templateSubmission({ ...valid, language: "en_US" }).language, "en_US");
  for (
    const invalid of [
      { ...valid, name: "Kampanya Yaz" },
      { ...valid, name: "" },
      { ...valid, language: "turkish" },
      { ...valid, category: "PROMOTION" },
      { ...valid, components: [] },
      { ...valid, components: [{ type: "FOOTER", text: "x" }] },
      { ...valid, components: [...body, ...body] },
      { ...valid, components: [{ type: "CAROUSEL" }] },
      { ...valid, components: "BODY" },
      { ...valid, components: [{ type: "BODY", text: "x".repeat(40000) }] },
    ]
  ) {
    assertThrows(() => templateSubmission(invalid), ApiError);
  }
});

Deno.test("header media accepts supported types within Meta's sample limits", () => {
  const png = btoa("\x89PNG fixture");
  const media = templateMedia({
    file_name: "kapak.png",
    mime_type: "image/png",
    base64: `data:image/png;base64,${png}`,
  });
  assertEquals(media.mimeType, "image/png");
  assertEquals(new TextDecoder().decode(media.bytes.slice(1)), "PNG fixture");
  for (
    const invalid of [
      { file_name: "a.gif", mime_type: "image/gif", base64: png },
      { file_name: "../a.png", mime_type: "image/png", base64: png },
      { file_name: "a.png", mime_type: "image/png", base64: "%%%" },
      { file_name: "a.png", mime_type: "image/png", base64: "" },
      {
        file_name: "a.png",
        mime_type: "image/png",
        base64: btoa("x".repeat(5 * 1024 * 1024 + 1)),
      },
    ]
  ) {
    assertThrows(() => templateMedia(invalid), ApiError);
  }
});

Deno.test("upload session paths cannot redirect the tenant token", () => {
  assertEquals(
    uploadSessionPath("upload:MTphdHRhY2htZW50==?sig=ARZqkGCA_uQ"),
    "upload:MTphdHRhY2htZW50==?sig=ARZqkGCA_uQ",
  );
  for (
    const invalid of [
      "123/messages",
      "upload:abc/../../me",
      "upload:abc?sig=x&next=https://evil.example",
      "https://evil.example/upload:abc",
      42,
    ]
  ) {
    assertThrows(() => uploadSessionPath(invalid), ApiError);
  }
});

Deno.test("resumable upload uses the tenant token and returns the handle", async () => {
  const calls: { url: string; init?: RequestInit }[] = [];
  const transport: typeof fetch = (input, init) => {
    const url = String(input);
    calls.push({ url, init });
    return Promise.resolve(
      new Response(
        JSON.stringify(
          calls.length === 1 ? { id: "upload:SESSION==?sig=SIG" } : { h: "4::aGFuZGxl" },
        ),
      ),
    );
  };
  const api = new WhatsAppApi("v23.0", fakeToken, transport);
  const handle = await api.uploadTemplateMedia("1234567890", {
    fileName: "kapak.png",
    mimeType: "image/png",
    bytes: new Uint8Array([1, 2, 3]),
  });
  assertEquals(handle, "4::aGFuZGxl");
  assertEquals(calls.length, 2);
  const session = new URL(calls[0].url);
  assertEquals(session.host, "graph.facebook.com");
  assertEquals(session.pathname, "/v23.0/1234567890/uploads");
  assertEquals(session.searchParams.get("file_length"), "3");
  assertEquals(session.searchParams.get("file_type"), "image/png");
  assertEquals(
    (calls[0].init?.headers as Record<string, string>).Authorization,
    `Bearer ${fakeToken}`,
  );
  assertEquals(calls[1].url, "https://graph.facebook.com/v23.0/upload:SESSION==?sig=SIG");
  const uploadHeaders = calls[1].init?.headers as Record<string, string>;
  assertEquals(uploadHeaders.Authorization, `OAuth ${fakeToken}`);
  assertEquals(uploadHeaders.file_offset, "0");
  assert(calls[1].init?.body instanceof Uint8Array);
});

Deno.test("resumable upload rejects provider errors and malformed sessions", async () => {
  const sequence = (...responses: unknown[]): typeof fetch => {
    let index = 0;
    return () => {
      const [value, status] = responses[index++] as [unknown, number];
      return Promise.resolve(new Response(JSON.stringify(value), { status }));
    };
  };
  const media = {
    fileName: "a.png",
    mimeType: "image/png",
    bytes: new Uint8Array([1]),
  };
  await assertRejects(
    () =>
      new WhatsAppApi("v23.0", fakeToken, sequence([{ id: "../me" }, 200]))
        .uploadTemplateMedia("1", media),
    ApiError,
  );
  await assertRejects(
    () =>
      new WhatsAppApi(
        "v23.0",
        fakeToken,
        sequence([{ id: "upload:S" }, 200], [{ error: { code: 190 } }, 401]),
      ).uploadTemplateMedia("1", media),
    GraphApiError,
  );
  await assertRejects(
    () =>
      new WhatsAppApi(
        "v23.0",
        fakeToken,
        sequence([{ id: "upload:S" }, 200], [{}, 200]),
      ).uploadTemplateMedia("1", media),
    ApiError,
  );
});
