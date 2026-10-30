// This is the authoritative contract for campaign forms and WhatsApp dispatch.
// Creation components are inspected, never forwarded to the messages endpoint.
export class TemplateInputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TemplateInputError";
  }
}

type JsonObject = Record<string, unknown>;
export type TemplateInput = {
  key: string;
  component: "header" | "body" | "button";
  kind: "text" | "image" | "video" | "document";
  variable?: string;
  index?: number;
  max_length: number;
};
export type ContactValues = {
  full_name?: string | null;
  phone?: string | null;
  email?: string | null;
};
const contactFields = new Set(["full_name", "phone", "email"]);

function object(value: unknown, description: string): JsonObject {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new TemplateInputError(`${description} must be an object`);
  }
  return value as JsonObject;
}

function text(value: unknown, description: string): string {
  if (typeof value !== "string") {
    throw new TemplateInputError(`${description} must be text`);
  }
  return value;
}

function variables(value: unknown): string[] {
  const source = text(value, "Template text");
  const names = [
    ...new Set(
      [...source.matchAll(/\{\{([1-9][0-9]*|[a-z][a-z0-9_]*)\}\}/g)].map(
        (match) => match[1],
      ),
    ),
  ];
  const remainder = source.replace(
    /\{\{([1-9][0-9]*|[a-z][a-z0-9_]*)\}\}/g,
    "",
  );
  if (remainder.includes("{{") || remainder.includes("}}")) {
    throw new TemplateInputError("Template contains an invalid variable");
  }
  if (names.length > 100) throw new TemplateInputError("Too many variables");
  const positional = names.filter((name) => /^[0-9]+$/.test(name));
  if (positional.length > 0) {
    if (positional.length !== names.length) {
      throw new TemplateInputError(
        "Named and positional variables cannot be mixed",
      );
    }
    names.sort((a, b) => Number(a) - Number(b));
    if (names.some((name, index) => name !== String(index + 1))) {
      throw new TemplateInputError(
        "Template variable positions must be consecutive",
      );
    }
  }
  return names;
}

export function templateInputs(raw: unknown): TemplateInput[] {
  const definitions = Array.isArray(raw)
    ? raw
    : object(raw, "Template").components;
  if (!Array.isArray(definitions) || definitions.length === 0) {
    throw new TemplateInputError(
      "Template definition missing; sync the template first",
    );
  }
  const inputs: TemplateInput[] = [];
  const seen = new Set<string>();
  for (const value of definitions) {
    const definition = object(value, "Component");
    const type = text(definition.type, "Component type").toLowerCase();
    if (seen.has(type))
      throw new TemplateInputError("Duplicate template component");
    seen.add(type);
    if (type === "header" || type === "body") {
      const format =
        type === "header"
          ? text(definition.format ?? "TEXT", "Header format").toLowerCase()
          : "text";
      if (["image", "video", "document"].includes(format)) {
        inputs.push({
          key: "header.media",
          component: "header",
          kind: format as "image" | "video" | "document",
          max_length: 2048,
        });
      } else if (format === "text") {
        const names = variables(definition.text);
        if (type === "header" && names.length > 1) {
          throw new TemplateInputError("Text headers support one variable");
        }
        for (const name of names) {
          inputs.push({
            key: `${type}.${name}`,
            component: type,
            kind: "text",
            variable: name,
            max_length: type === "header" ? 60 : 1024,
          });
        }
      } else {
        throw new TemplateInputError(`Unsupported header format: ${format}`);
      }
    } else if (type === "buttons") {
      if (
        !Array.isArray(definition.buttons) ||
        definition.buttons.length > 10
      ) {
        throw new TemplateInputError("Invalid template buttons");
      }
      for (const [index, value] of definition.buttons.entries()) {
        const button = object(value, "Button");
        const kind = text(button.type, "Button type").toLowerCase();
        if (kind === "url") {
          const url = text(button.url, "Button URL");
          const names = variables(url);
          if (names.length > 0) {
            if (
              names.length !== 1 ||
              names[0] !== "1" ||
              !url.endsWith("{{1}}")
            ) {
              throw new TemplateInputError(
                "URL buttons support one positional suffix",
              );
            }
            inputs.push({
              key: `button.${index}`,
              component: "button",
              kind: "text",
              index,
              max_length: 2000,
            });
          }
        } else if (kind !== "phone_number" && kind !== "quick_reply") {
          throw new TemplateInputError(`Unsupported button type: ${kind}`);
        }
        // Static phone/URL and ordinary quick-reply buttons need no send parameter.
      }
    } else if (type === "footer") {
      if (variables(definition.text).length > 0) {
        throw new TemplateInputError("Footer variables are not supported");
      }
    } else {
      throw new TemplateInputError(`Unsupported component type: ${type}`);
    }
  }
  if (!seen.has("body")) throw new TemplateInputError("Template body missing");
  const styles = new Set(
    inputs
      .filter((input) => input.variable)
      .map((input) =>
        /^[0-9]+$/.test(input.variable!) ? "positional" : "named",
      ),
  );
  if (styles.size > 1) {
    throw new TemplateInputError(
      "Named and positional variables cannot be mixed",
    );
  }
  return inputs;
}

function validateText(value: unknown, input: TemplateInput): string {
  const result = text(value, input.key).trim();
  if (
    !result ||
    result.length > input.max_length ||
    /[\r\n\t\x00-\x1f]| {4}/.test(result)
  ) {
    throw new TemplateInputError(`Invalid value for ${input.key}`);
  }
  return result;
}

function validateMedia(
  value: unknown,
  source: unknown,
  input: TemplateInput,
): string {
  const result = text(value, input.key).trim();
  if (source === "media_id") {
    if (!/^[0-9]{1,100}$/.test(result)) {
      throw new TemplateInputError(`Invalid media ID for ${input.key}`);
    }
    return result;
  }
  if (source !== "media_link" || result.length > input.max_length) {
    throw new TemplateInputError(`Media link or ID required for ${input.key}`);
  }
  let url: URL;
  try {
    url = new URL(result);
  } catch {
    throw new TemplateInputError(`Invalid HTTPS media link for ${input.key}`);
  }
  // Links are passed to Meta, never fetched by this server. Exclude credentials,
  // local hostnames and IP literals; availability/content type is provider-validated.
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.hash ||
    !url.hostname.includes(".") ||
    /^[0-9.]+$/.test(url.hostname) ||
    url.hostname.includes(":") ||
    /\.(localhost|local|internal)$/.test(url.hostname)
  ) {
    throw new TemplateInputError(
      `Public HTTPS media link required for ${input.key}`,
    );
  }
  return result;
}

export function validateTemplateBindings(
  inputs: TemplateInput[],
  raw: unknown,
): JsonObject {
  const bindings = object(raw, "Template bindings");
  const expected = new Set(inputs.map((input) => input.key));
  if (Object.keys(bindings).some((key) => !expected.has(key))) {
    throw new TemplateInputError("Bindings do not match the selected template");
  }
  for (const input of inputs) {
    const binding = object(bindings[input.key], `Binding ${input.key}`);
    const allowed =
      binding.source === "contact"
        ? ["source", "field", "fallback"]
        : ["source", "value"];
    if (Object.keys(binding).some((key) => !allowed.includes(key))) {
      throw new TemplateInputError(`Unknown binding option for ${input.key}`);
    }
    if (input.kind !== "text") {
      validateMedia(binding.value, binding.source, input);
    } else if (binding.source === "literal") {
      validateText(binding.value, input);
    } else if (binding.source === "contact") {
      if (
        typeof binding.field !== "string" ||
        !contactFields.has(binding.field)
      ) {
        throw new TemplateInputError(
          `Unsupported contact field for ${input.key}`,
        );
      }
      if (binding.fallback !== undefined) validateText(binding.fallback, input);
    } else {
      throw new TemplateInputError(
        `Text or contact value required for ${input.key}`,
      );
    }
  }
  return bindings;
}

export function buildTemplateComponents(
  rawDefinition: unknown,
  rawBindings: unknown,
  contact: ContactValues,
): JsonObject[] {
  const inputs = templateInputs(rawDefinition);
  const bindings = validateTemplateBindings(inputs, rawBindings);
  const components: JsonObject[] = [];
  for (const input of inputs) {
    const binding = bindings[input.key] as JsonObject;
    let parameter: JsonObject;
    if (input.kind === "text") {
      const contactValue =
        binding.source === "contact"
          ? contact[binding.field as keyof ContactValues]
          : undefined;
      const value =
        binding.source === "contact"
          ? contactValue?.trim() || binding.fallback
          : binding.value;
      parameter = { type: "text", text: validateText(value, input) };
      if (input.variable && !/^[0-9]+$/.test(input.variable)) {
        parameter.parameter_name = input.variable;
      }
    } else {
      parameter = {
        type: input.kind,
        [input.kind]: {
          [binding.source === "media_id" ? "id" : "link"]: validateMedia(
            binding.value,
            binding.source,
            input,
          ),
        },
      };
    }
    if (input.component === "button") {
      components.push({
        type: "button",
        sub_type: "url",
        index: String(input.index),
        parameters: [parameter],
      });
    } else {
      let component = components.find((item) => item.type === input.component);
      if (!component) {
        component = { type: input.component, parameters: [] };
        components.push(component);
      }
      (component.parameters as JsonObject[]).push(parameter);
    }
  }
  return components;
}
