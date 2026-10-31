import { ApiError } from "./http.ts";

export type SyncedTemplate = {
  id: string;
  name: string;
  language: string;
  category: string;
  status: string;
  components: unknown[];
};

// Validate the whole provider page before any database mutation. Creation-only
// fields stay in the definition; send-time construction uses template_parameters.
export function templatePage(
  payload: Record<string, unknown>,
  previousCursor?: string,
) {
  if (!Array.isArray(payload.data) || payload.data.length > 100) {
    throw new ApiError(
      502,
      "invalid_template_page",
      "WhatsApp template page unavailable",
    );
  }
  const identities = new Set<string>();
  const templates: SyncedTemplate[] = payload.data.map((value) => {
    if (
      !value || typeof value !== "object" || Array.isArray(value) ||
      typeof value.id !== "string" || !/^[0-9]{1,40}$/.test(value.id) ||
      typeof value.name !== "string" ||
      !/^[a-z0-9_]{1,512}$/.test(value.name) ||
      typeof value.language !== "string" ||
      !/^[a-z]{2,3}(?:_[A-Za-z]{2,4})?$/.test(value.language) ||
      typeof value.category !== "string" ||
      !/^[A-Z_]{1,40}$/.test(value.category) ||
      typeof value.status !== "string" ||
      !/^[A-Z_]{1,40}$/.test(value.status) ||
      !Array.isArray(value.components) ||
      JSON.stringify(value.components).length > 65536
    ) {
      throw new ApiError(
        502,
        "invalid_template_page",
        "WhatsApp template definition unavailable",
      );
    }
    const key = `${value.name}:${value.language}`;
    if (identities.has(key)) {
      throw new ApiError(
        502,
        "ambiguous_template_page",
        "WhatsApp returned duplicate template identities",
      );
    }
    identities.add(key);
    return {
      id: value.id,
      name: value.name,
      language: value.language,
      category: value.category,
      status: value.status,
      components: value.components,
    };
  });
  const paging = payload.paging as {
    next?: unknown;
    cursors?: { after?: unknown };
  } | undefined;
  let cursor: string | null = null;
  if (paging?.next) {
    const after = paging.cursors?.after;
    if (
      typeof after !== "string" || !after || after.length > 2048 ||
      after === previousCursor
    ) {
      throw new ApiError(
        502,
        "invalid_template_cursor",
        "WhatsApp template pagination unavailable",
      );
    }
    cursor = after;
  }
  return { templates, cursor };
}
