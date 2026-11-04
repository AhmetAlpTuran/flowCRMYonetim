import { ApiError } from "./http.ts";

// Server-side validation for new template submissions and header media uploads.
// Provider-side review remains authoritative; these checks reject malformed or
// oversized input before a tenant token is used.

export const TEMPLATE_CATEGORIES = [
  "MARKETING",
  "UTILITY",
  "AUTHENTICATION",
] as const;
const COMPONENT_TYPES = new Set(["HEADER", "BODY", "FOOTER", "BUTTONS"]);
const MAX_COMPONENTS_BYTES = 32768;

export type TemplateSubmission = {
  name: string;
  language: string;
  category: (typeof TEMPLATE_CATEGORIES)[number];
  components: Record<string, unknown>[];
};

function invalid(message: string): never {
  throw new ApiError(400, "invalid_template", message);
}

export function templateSubmission(
  body: Record<string, unknown>,
): TemplateSubmission {
  const { name, language, category, components } = body;
  if (typeof name !== "string" || !/^[a-z0-9_]{1,512}$/.test(name)) {
    invalid("Template name must use lowercase letters, digits and underscores");
  }
  if (
    typeof language !== "string" ||
    !/^[a-z]{2,3}(_[A-Za-z]{2,4})?$/.test(language)
  ) {
    invalid("Template language code required, for example tr or en_US");
  }
  if (
    typeof category !== "string" ||
    !(TEMPLATE_CATEGORIES as readonly string[]).includes(category)
  ) {
    invalid("Template category must be MARKETING, UTILITY or AUTHENTICATION");
  }
  if (
    !Array.isArray(components) || components.length === 0 ||
    components.length > 10
  ) {
    invalid("Template needs between one and ten components");
  }
  if (new TextEncoder().encode(JSON.stringify(components)).length > MAX_COMPONENTS_BYTES) {
    invalid("Template components are too large");
  }
  const seen = new Set<string>();
  for (const component of components) {
    if (
      !component || typeof component !== "object" || Array.isArray(component)
    ) {
      invalid("Each template component must be an object");
    }
    const type = (component as Record<string, unknown>).type;
    if (typeof type !== "string" || !COMPONENT_TYPES.has(type)) {
      invalid("Unsupported template component type");
    }
    if (seen.has(type)) invalid(`Template may contain only one ${type} component`);
    seen.add(type);
  }
  if (!seen.has("BODY")) invalid("Template BODY component required");
  return {
    name,
    language,
    category: category as TemplateSubmission["category"],
    components: components as Record<string, unknown>[],
  };
}

// Meta's documented header sample limits per media family.
const MEDIA_LIMITS: Record<string, number> = {
  "image/jpeg": 5 * 1024 * 1024,
  "image/png": 5 * 1024 * 1024,
  "video/mp4": 16 * 1024 * 1024,
  "application/pdf": 16 * 1024 * 1024,
};

export function maxTemplateMediaBytes(): number {
  return Math.max(...Object.values(MEDIA_LIMITS));
}

export type TemplateMedia = {
  fileName: string;
  mimeType: string;
  bytes: Uint8Array<ArrayBuffer>;
};

export function templateMedia(body: Record<string, unknown>): TemplateMedia {
  const { file_name: fileName, mime_type: mimeType, base64 } = body;
  if (
    typeof fileName !== "string" || fileName.length < 1 ||
    fileName.length > 255 || /[\u0000-\u001f\/\\]/.test(fileName)
  ) {
    throw new ApiError(400, "invalid_media", "Valid file name required");
  }
  if (typeof mimeType !== "string" || !(mimeType in MEDIA_LIMITS)) {
    throw new ApiError(
      415,
      "unsupported_media_type",
      "Header media must be JPEG, PNG, MP4 or PDF",
    );
  }
  if (typeof base64 !== "string" || base64.length === 0) {
    throw new ApiError(400, "invalid_media", "Media content required");
  }
  const encoded = base64.includes(",") ? base64.slice(base64.indexOf(",") + 1) : base64;
  let binary: string;
  try {
    binary = atob(encoded);
  } catch {
    throw new ApiError(400, "invalid_media", "Media content must be base64");
  }
  if (binary.length === 0 || binary.length > MEDIA_LIMITS[mimeType]) {
    throw new ApiError(413, "media_too_large", "Media file is too large");
  }
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return { fileName, mimeType, bytes };
}

// Upload-session IDs returned by Meta look like "upload:<opaque>?sig=<opaque>".
// Only that shape is accepted so a provider response can never redirect the
// tenant token to another Graph path.
export function uploadSessionPath(value: unknown): string {
  if (
    typeof value !== "string" || value.length > 2048 ||
    !/^upload:[A-Za-z0-9_\-=:.%+]+(\?sig=[A-Za-z0-9_\-=:.%+]+)?$/.test(value)
  ) {
    throw new ApiError(
      502,
      "whatsapp_invalid_response",
      "WhatsApp upload session unavailable",
    );
  }
  return value;
}
