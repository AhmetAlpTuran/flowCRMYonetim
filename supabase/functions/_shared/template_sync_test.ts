import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ApiError } from "./http.ts";
import { templatePage } from "./template_sync.ts";

const definition = {
  id: "123",
  name: "welcome",
  language: "tr",
  category: "UTILITY",
  status: "APPROVED",
  components: [{ type: "BODY", text: "Merhaba" }],
};

Deno.test("template pages preserve language identity and return only pagination cursors", () => {
  const page = templatePage({
    data: [definition, { ...definition, id: "456", language: "en_US" }],
    paging: {
      next: "https://untrusted.invalid/never-follow",
      cursors: { after: "cursor-2" },
    },
  });
  assertEquals(page.templates.map((value) => value.language), ["tr", "en_US"]);
  assertEquals(page.cursor, "cursor-2");
  assertEquals(templatePage({ data: [] }).cursor, null);
});

Deno.test("template sync rejects ambiguous pages, malformed definitions and repeated cursors", () => {
  for (
    const data of [
      null,
      {},
      [null],
      [definition, definition],
      [{ ...definition, components: {} }],
      [{ ...definition, id: "https://other.invalid" }],
      [{ ...definition, name: "" }],
    ]
  ) {
    assertThrows(() => templatePage({ data }), ApiError);
  }
  assertThrows(
    () => templatePage({ data: [], paging: { next: "ignored" } }),
    ApiError,
  );
  assertThrows(
    () =>
      templatePage({
        data: [],
        paging: { next: "ignored", cursors: { after: "same" } },
      }, "same"),
    ApiError,
  );
});
