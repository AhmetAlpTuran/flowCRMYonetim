import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildTemplateComponents,
  TemplateInputError,
  templateInputs,
} from "./template_parameters.ts";

const body = (value: string) => [{ type: "BODY", text: value }];
const literal = (value: string) => ({ source: "literal", value });

Deno.test(
  "static definitions and examples never become send parameters",
  () => {
    assertEquals(
      buildTemplateComponents(
        [
          { type: "HEADER", format: "TEXT", text: "News" },
          { type: "BODY", text: "Hello", example: { body_text: [["unused"]] } },
          { type: "FOOTER", text: "Thank you" },
          { type: "BUTTONS", buttons: [{ type: "QUICK_REPLY", text: "Stop" }] },
        ],
        {},
        {},
      ),
      [],
    );
  },
);

Deno.test(
  "positional variables are sorted and repeated occurrences need one value",
  () => {
    assertEquals(
      buildTemplateComponents(
        body("{{2}} for {{1}} and {{1}}"),
        {
          "body.1": {
            source: "contact",
            field: "full_name",
            fallback: "Customer",
          },
          "body.2": literal("Offer"),
        },
        { full_name: null },
      ),
      [
        {
          type: "body",
          parameters: [
            { type: "text", text: "Customer" },
            { type: "text", text: "Offer" },
          ],
        },
      ],
    );
  },
);

Deno.test(
  "named values carry parameter_name and resolve only allowed contact fields",
  () => {
    assertEquals(
      buildTemplateComponents(
        { components: body("Hi {{customer_name}}") },
        {
          "body.customer_name": { source: "contact", field: "full_name" },
        },
        { full_name: "Ada" },
      ),
      [
        {
          type: "body",
          parameters: [
            { type: "text", text: "Ada", parameter_name: "customer_name" },
          ],
        },
      ],
    );
    assertThrows(
      () =>
        buildTemplateComponents(
          body("Hi {{1}}"),
          {
            "body.1": { source: "contact", field: "tenant_id" },
          },
          {},
        ),
      TemplateInputError,
    );
  },
);

Deno.test(
  "header text and media use their own send parameter structures",
  () => {
    assertEquals(
      buildTemplateComponents(
        [
          { type: "HEADER", format: "TEXT", text: "Hello {{1}}" },
          ...body("News"),
        ],
        { "header.1": literal("Ada") },
        {},
      ),
      [{ type: "header", parameters: [{ type: "text", text: "Ada" }] }],
    );
    for (const kind of ["image", "video", "document"]) {
      const definition = [
        {
          type: "HEADER",
          format: kind.toUpperCase(),
          example: { header_handle: ["creation-handle-is-not-a-media-id"] },
        },
        ...body("News"),
      ];
      for (const [source, value, field] of [
        ["media_link", "https://cdn.example.com/file", "link"],
        ["media_id", "123456789", "id"],
      ]) {
        assertEquals(
          buildTemplateComponents(
            definition,
            {
              "header.media": { source, value },
            },
            {},
          ),
          [
            {
              type: "header",
              parameters: [{ type: kind, [kind]: { [field]: value } }],
            },
          ],
        );
      }
    }
  },
);

Deno.test("dynamic URL index includes preceding static buttons", () => {
  assertEquals(
    buildTemplateComponents(
      [
        ...body("Track your order"),
        {
          type: "BUTTONS",
          buttons: [
            {
              type: "PHONE_NUMBER",
              phone_number: "+905550000000",
              text: "Call",
            },
            { type: "URL", url: "https://example.com/{{1}}", text: "Track" },
          ],
        },
      ],
      { "button.1": literal("order-123") },
      {},
    ),
    [
      {
        type: "button",
        sub_type: "url",
        index: "1",
        parameters: [{ type: "text", text: "order-123" }],
      },
    ],
  );
});

Deno.test(
  "missing, surplus, empty and malformed values fail before network I/O",
  () => {
    for (const bindings of [
      {},
      { "body.1": literal("") },
      { "body.1": literal("line\nbreak") },
      { "body.1": literal("x".repeat(1025)) },
      { "body.1": literal("valid"), "body.2": literal("extra") },
      { "body.1": { source: "contact", field: "full_name" } },
      { "body.1": { source: "literal", value: "valid", text: "injection" } },
    ])
      assertThrows(
        () => buildTemplateComponents(body("Hi {{1}}"), bindings, {}),
        TemplateInputError,
      );
  },
);

Deno.test(
  "media rejects creation handles and local or credentialed URLs",
  () => {
    const definition = [{ type: "HEADER", format: "IMAGE" }, ...body("News")];
    for (const value of [
      "http://example.com/a",
      "https://localhost/a",
      "https://127.0.0.1/a",
      "https://[::1]/a",
      "https://name:password@example.com/a",
      "not-a-url",
    ]) {
      assertThrows(
        () =>
          buildTemplateComponents(
            definition,
            {
              "header.media": { source: "media_link", value },
            },
            {},
          ),
        TemplateInputError,
      );
    }
    assertThrows(
      () =>
        buildTemplateComponents(
          definition,
          {
            "header.media": { source: "media_id", value: "4::upload-handle" },
          },
          {},
        ),
      TemplateInputError,
    );
  },
);

Deno.test("invalid and unsupported definitions are explicitly rejected", () => {
  for (const definition of [
    null,
    {},
    [],
    body("{{0}}"),
    body("{{2}}"),
    body("{{1}} {{name}}"),
    body("{{not closed"),
    [...body("Hi"), ...body("Duplicate")],
    [{ type: "HEADER", format: "LOCATION" }, ...body("Hi")],
    [...body("Hi"), { type: "CAROUSEL", cards: [] }],
    [...body("Hi"), { type: "BUTTONS", buttons: [{ type: "FLOW" }] }],
  ])
    assertThrows(() => templateInputs(definition), TemplateInputError);
});
