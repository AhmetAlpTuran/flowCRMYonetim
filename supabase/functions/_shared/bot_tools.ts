// Catalog and booking tools the AI assistant can call. Every tool runs through a
// service-only database function that is tenant scoped and bound to the current
// conversation (supabase/migrations/20261107090000_catalog_bookings_leads.sql).
// The customer's phone number always comes from the conversation, never the model.

export type CatalogField = {
  key: string;
  label: string;
  type: string;
  options?: string[];
};
export type CatalogType = {
  key: string;
  name: string;
  kind: "bookable" | "listing";
  booking_unit: "night" | "day" | "hour" | null;
  fields: CatalogField[];
};
export type ToolCall = { call_id: string; name: string; arguments: string };
export type ToolRunner = (call: ToolCall) => Promise<unknown>;

/** Minimal database surface the tools need; the worker passes the service client. */
export type ToolDatabase = {
  rpc: (
    name: string,
    params: Record<string, unknown>,
  ) => Promise<{ data: unknown; error: { code?: string } | null }>;
  resourceUnit: (resourceId: string) => Promise<string | null | undefined>;
  conversationBookings: () => Promise<unknown[]>;
};

/** Türkiye has used UTC+3 all year since 2016. */
const ISTANBUL_OFFSET = "+03:00";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;
export const LEAD_KINDS = [
  "inquiry",
  "test_drive",
  "trade_in",
  "financing",
  "booking_request",
  "other",
] as const;

const nullable = (type: string, extra: Record<string, unknown> = {}) => ({
  type: [type, "null"],
  ...extra,
});
const dateArgs = {
  check_in_date: nullable("string", { description: "Nightly/daily stays: first day, YYYY-MM-DD." }),
  check_out_date: nullable("string", {
    description: "Nightly stays: check-out day; daily: last day. YYYY-MM-DD.",
  }),
  date: nullable("string", { description: "Hourly bookings: day, YYYY-MM-DD." }),
  start_time: nullable("string", { description: "Hourly bookings: HH:MM (24h)." }),
  hours: nullable("integer", { description: "Hourly bookings: duration in hours (1-12)." }),
};
const dateKeys = Object.keys(dateArgs);

function tool(
  name: string,
  description: string,
  properties: Record<string, unknown>,
) {
  return {
    type: "function",
    name,
    description,
    strict: true,
    parameters: {
      type: "object",
      additionalProperties: false,
      required: Object.keys(properties),
      properties,
    },
  };
}

/** Responses API tool definitions for this business's catalog. */
export function catalogToolDefinitions(types: CatalogType[]): Record<string, unknown>[] {
  if (types.length === 0) return [];
  const typeHelp = types.map((t) => {
    const fields = t.fields.map((f) =>
      `${f.key} (${f.label}, ${f.type}${f.options?.length ? `: ${f.options.join("/")}` : ""})`
    ).join(", ");
    const unit = t.kind === "bookable" ? `, booked per ${t.booking_unit}` : ", listing";
    return `${t.key} = ${t.name}${unit}; fields: ${fields || "none"}`;
  }).join(". ");
  const definitions = [
    tool(
      "search_catalog",
      `Search this business's active items. Types: ${typeHelp}. Never invent items, prices or features.`,
      {
        type_key: nullable("string", { enum: [...types.map((t) => t.key), null] }),
        query: nullable("string", { description: "Words to match in name or description." }),
        filters: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: ["field", "equals", "min", "max"],
            properties: {
              field: { type: "string" },
              equals: nullable("string"),
              min: nullable("number"),
              max: nullable("number"),
            },
          },
        },
        price_min: nullable("number"),
        price_max: nullable("number"),
      },
    ),
    tool(
      "create_lead",
      "Record a customer request for staff follow-up: test drive, trade-in, financing, callback or other.",
      {
        kind: { type: "string", enum: [...LEAD_KINDS] },
        resource_id: nullable("string"),
        note: nullable("string", { description: "Short summary of what the customer wants." }),
        preferred_date: nullable("string", { description: "YYYY-MM-DD" }),
        preferred_time: nullable("string", { description: "HH:MM" }),
        customer_name: nullable("string"),
      },
    ),
  ];
  if (types.some((t) => t.kind === "bookable")) {
    definitions.push(
      tool(
        "check_availability",
        "Check whether a bookable item is free for the given dates.",
        { resource_id: { type: "string" }, ...dateArgs },
      ),
      tool(
        "hold_booking",
        "Place a 15-minute hold for the customer. Afterwards tell them the details and ask for explicit confirmation.",
        { resource_id: { type: "string" }, ...dateArgs, customer_name: nullable("string") },
      ),
      tool(
        "confirm_booking",
        "Confirm a hold only after the customer clearly agreed in a later message.",
        { booking_id: { type: "string" } },
      ),
      tool(
        "cancel_booking",
        "Cancel this customer's hold or booking when they ask.",
        { booking_id: { type: "string" } },
      ),
      tool(
        "my_bookings",
        "List this customer's holds and bookings in this conversation.",
        {},
      ),
    );
  }
  return definitions;
}

export class ToolInputError extends Error {}

/** Converts tool date arguments into the database's half-open [start, end). */
export function periodFor(unit: string, args: Record<string, unknown>): { start: string; end: string } {
  const day = (value: unknown, label: string) => {
    if (typeof value !== "string" || !DATE.test(value) || Number.isNaN(Date.parse(value))) {
      throw new ToolInputError(`${label} must be YYYY-MM-DD`);
    }
    return value;
  };
  const at = (date: string, time: string) => `${date}T${time}:00${ISTANBUL_OFFSET}`;
  if (unit === "hour") {
    const date = day(args.date, "date");
    const time = typeof args.start_time === "string" && TIME.test(args.start_time)
      ? args.start_time
      : (() => {
        throw new ToolInputError("start_time must be HH:MM");
      })();
    const hours = Number.isInteger(args.hours) ? Number(args.hours) : 1;
    if (hours < 1 || hours > 12) throw new ToolInputError("hours must be 1-12");
    const start = new Date(at(date, time));
    return {
      start: start.toISOString(),
      end: new Date(start.getTime() + hours * 3600000).toISOString(),
    };
  }
  const first = day(args.check_in_date, "check_in_date");
  const last = day(args.check_out_date, "check_out_date");
  if (unit === "night") {
    if (last <= first) throw new ToolInputError("check_out_date must be after check_in_date");
    // Nightly stays: 14:00 check-in, 11:00 check-out (Istanbul).
    return { start: new Date(at(first, "14:00")).toISOString(), end: new Date(at(last, "11:00")).toISOString() };
  }
  if (last < first) throw new ToolInputError("check_out_date must not be before check_in_date");
  const end = new Date(at(last, "00:00"));
  end.setUTCDate(end.getUTCDate() + 1);
  return { start: new Date(at(first, "00:00")).toISOString(), end: end.toISOString() };
}

async function requestKey(jobId: string, name: string, args: Record<string, unknown>) {
  // Same job + tool + arguments => same key, so a retried job never doubles a hold.
  const canonical = JSON.stringify(Object.keys(args).sort().map((k) => [k, args[k]]));
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${name}:${canonical}`)),
  );
  const hex = Array.from(digest.slice(0, 12), (b) => b.toString(16).padStart(2, "0")).join("");
  return `${jobId}:${name}:${hex}`;
}

const errorCodes: Record<string, string> = {
  P0015: "not_available",
  P0016: "hold_expired_or_cancelled",
  P0002: "not_found",
  "22023": "invalid_input",
  "42501": "not_allowed",
};

function text(value: unknown, max: number): string | null {
  return typeof value === "string" && value.trim() ? value.trim().slice(0, max) : null;
}

function id(value: unknown, label: string): string {
  if (typeof value !== "string" || !UUID.test(value)) throw new ToolInputError(`${label} is not a valid id`);
  return value;
}

/** Runs one tool call; failures become structured results the model can explain. */
export function createToolRunner(
  db: ToolDatabase,
  scope: { tenantId: string; conversationId: string; jobId: string },
): ToolRunner {
  const call = async (name: string, params: Record<string, unknown>) => {
    const { data, error } = await db.rpc(name, params);
    if (error) return { error: errorCodes[error.code ?? ""] ?? "unavailable" };
    return data;
  };
  const base = { p_tenant_id: scope.tenantId };
  return async ({ name, arguments: raw }) => {
    let args: Record<string, unknown>;
    try {
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
      args = parsed;
    } catch {
      return { error: "invalid_input", message: "Arguments must be a JSON object" };
    }
    try {
      switch (name) {
        case "search_catalog": {
          const filters: Record<string, unknown> = {};
          for (const f of Array.isArray(args.filters) ? args.filters.slice(0, 8) : []) {
            if (!f || typeof f.field !== "string" || !/^[a-z][a-z0-9_]{0,39}$/.test(f.field)) continue;
            if (typeof f.min === "number" || typeof f.max === "number") {
              filters[f.field] = { min: f.min ?? null, max: f.max ?? null };
            } else if (typeof f.equals === "string") filters[f.field] = f.equals.slice(0, 80);
          }
          if (typeof args.price_min === "number" || typeof args.price_max === "number") {
            filters.price = { min: args.price_min ?? null, max: args.price_max ?? null };
          }
          return await call("bot_search_resources", {
            ...base,
            p_type_key: text(args.type_key, 40),
            p_query: text(args.query, 100),
            p_filters: filters,
            p_limit: 5,
          });
        }
        case "check_availability":
        case "hold_booking": {
          const resource = id(args.resource_id, "resource_id");
          const unit = await db.resourceUnit(resource);
          if (!unit) return { error: "not_found" };
          const { start, end } = periodFor(unit, args);
          if (name === "check_availability") {
            return await call("bot_check_availability", {
              ...base,
              p_resource_id: resource,
              p_start: start,
              p_end: end,
            });
          }
          const keyArgs = Object.fromEntries(
            ["resource_id", ...dateKeys].map((k) => [k, args[k] ?? null]),
          );
          return await call("bot_create_booking_hold", {
            ...base,
            p_conversation_id: scope.conversationId,
            p_resource_id: resource,
            p_start: start,
            p_end: end,
            p_customer_name: text(args.customer_name, 120),
            p_request_key: await requestKey(scope.jobId, name, keyArgs),
            p_hold_minutes: 15,
          });
        }
        case "confirm_booking":
        case "cancel_booking":
          return await call("bot_set_booking_status", {
            ...base,
            p_conversation_id: scope.conversationId,
            p_booking_id: id(args.booking_id, "booking_id"),
            p_status: name === "confirm_booking" ? "confirmed" : "cancelled",
          });
        case "my_bookings":
          return { bookings: await db.conversationBookings() };
        case "create_lead": {
          if (!LEAD_KINDS.includes(args.kind as typeof LEAD_KINDS[number])) {
            throw new ToolInputError("kind is not supported");
          }
          const date = text(args.preferred_date, 10);
          const time = text(args.preferred_time, 5);
          if (date && !DATE.test(date)) throw new ToolInputError("preferred_date must be YYYY-MM-DD");
          if (time && !TIME.test(time)) throw new ToolInputError("preferred_time must be HH:MM");
          const note = text(args.note, 1000);
          return await call("bot_create_lead", {
            ...base,
            p_conversation_id: scope.conversationId,
            p_kind: args.kind,
            p_resource_id: args.resource_id == null ? null : id(args.resource_id, "resource_id"),
            p_details: note ? { note } : {},
            p_preferred_at: date ? `${date}T${time ?? "10:00"}:00${ISTANBUL_OFFSET}` : null,
            p_customer_name: text(args.customer_name, 120),
            p_request_key: await requestKey(scope.jobId, name, {
              kind: args.kind,
              resource_id: args.resource_id ?? null,
              preferred_date: date,
            }),
          });
        }
        default:
          return { error: "unknown_tool" };
      }
    } catch (error) {
      if (error instanceof ToolInputError) return { error: "invalid_input", message: error.message };
      return { error: "unavailable" };
    }
  };
}

/** Today's date in Istanbul, for resolving "this weekend" and similar. */
export function istanbulToday(now = new Date()): string {
  const local = new Date(now.getTime() + 3 * 3600000);
  const days = ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"];
  return `${local.toISOString().slice(0, 10)} (${days[local.getUTCDay()]})`;
}

// --- Booking confirmation buttons --------------------------------------------

export type ReplyButton = { id: string; title: string };
export type ButtonTap = { action: "confirm" | "cancel"; bookingId: string };

/** Buttons for a reply that placed exactly one fresh hold; none otherwise. */
export function bookingButtons(heldBookingIds: string[]): ReplyButton[] | undefined {
  const unique = [...new Set(heldBookingIds)];
  if (unique.length !== 1 || !UUID.test(unique[0])) return undefined;
  return [
    { id: `booking:confirm:${unique[0]}`, title: "Onayla" },
    { id: `booking:cancel:${unique[0]}`, title: "İptal" },
  ];
}

/** Reads a tapped reply button from the stored inbound message. */
export function parseButtonTap(providerContent: unknown): ButtonTap | null {
  const content = providerContent as { interactive?: { button_reply?: { id?: unknown } } } | null;
  const id = content?.interactive?.button_reply?.id;
  if (typeof id !== "string") return null;
  const match = /^booking:(confirm|cancel):([0-9a-f-]{36})$/i.exec(id);
  if (!match || !UUID.test(match[2])) return null;
  return { action: match[1].toLowerCase() as ButtonTap["action"], bookingId: match[2].toLowerCase() };
}

function istanbulDate(iso: string): string {
  const local = new Date(new Date(iso).getTime() + 3 * 3600000);
  const two = (n: number) => String(n).padStart(2, "0");
  return `${two(local.getUTCDate())}.${two(local.getUTCMonth() + 1)}.${local.getUTCFullYear()}`;
}

/** Fixed Turkish reply after a button tap (no model call). */
export function buttonReplyText(
  tap: ButtonTap,
  result: unknown,
  booking?: { name?: string; start?: string; end?: string },
): string {
  const error = (result as { error?: string } | null)?.error;
  if (error === "hold_expired_or_cancelled") {
    return "Bu ön rezervasyonun süresi dolmuş. Tarihler hâlâ uygunsa yeniden ayırmamı ister misiniz?";
  }
  if (error) return "Bu rezervasyonu şu anda güncelleyemedim. Bir temsilcimiz kısa süre içinde yardımcı olacak.";
  if (tap.action === "cancel") {
    return "Ön rezervasyonunuz iptal edildi. Başka bir tarih için yardımcı olabilirim.";
  }
  const when = booking?.start && booking?.end
    ? ` (${istanbulDate(booking.start)} – ${istanbulDate(booking.end)})`
    : "";
  return `Rezervasyonunuz onaylandı${booking?.name ? `: ${booking.name}` : ""}${when}. Teşekkür ederiz!`;
}

/** Postgres tstzrange text -> ISO start/end, e.g. ["2026-11-21 11:00:00+00","...") */
export function parsePeriod(value: unknown): { start: string; end: string } | null {
  if (typeof value !== "string") return null;
  const parts = value.slice(1, -1).split(",").map((p) => p.trim().replaceAll('"', ""));
  if (parts.length !== 2) return null;
  const iso = (text: string) => {
    const fixed = text.replace(" ", "T").replace(/([+-]\d\d)$/, "$1:00");
    const date = new Date(fixed);
    return Number.isNaN(date.getTime()) ? null : date.toISOString();
  };
  const start = iso(parts[0]);
  const end = iso(parts[1]);
  return start && end ? { start, end } : null;
}

/**
 * Wraps a runner to remember holds placed during one reply, so the reply can carry
 * confirmation buttons. Confirming or cancelling in the same reply removes the hold.
 */
export function trackHolds(runner: ToolRunner): { runner: ToolRunner; held: () => string[] } {
  const held = new Set<string>();
  return {
    held: () => [...held],
    runner: async (call) => {
      const result = await runner(call) as Record<string, unknown> | null;
      const id = typeof result?.booking_id === "string" ? result.booking_id : null;
      if (id && call.name === "hold_booking" && result?.status === "hold") held.add(id);
      if (id && (call.name === "confirm_booking" || call.name === "cancel_booking")) held.delete(id);
      return result;
    },
  };
}
