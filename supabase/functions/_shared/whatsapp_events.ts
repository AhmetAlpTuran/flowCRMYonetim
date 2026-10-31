import { ApiError } from "./http.ts";

type ObjectValue = Record<string, unknown>;
export type WhatsAppEvent = {
  event_key: string;
  waba_id: string;
  phone_number_id: string;
  kind: "message" | "status";
  message_id: string;
  occurred_at: string;
  payload: ObjectValue;
};
const invalid = () =>
  new ApiError(400, "invalid_webhook_event", "Invalid webhook event");
function object(value: unknown): ObjectValue {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw invalid();
  }
  return value as ObjectValue;
}
function items(value: unknown): unknown[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 1000) throw invalid();
  return value;
}
function identifier(value: unknown, pattern: RegExp): string {
  if (typeof value !== "string" || !pattern.test(value)) throw invalid();
  return value;
}
function timestamp(value: unknown): string {
  const raw = identifier(value, /^[0-9]{1,12}$/);
  const seconds = Number(raw);
  if (seconds <= 0 || seconds > 253402300799) throw invalid();
  return new Date(seconds * 1000).toISOString();
}
async function hash(parts: unknown[]): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(JSON.stringify(parts)),
  );
  return [...new Uint8Array(digest)].map((value) =>
    value.toString(16).padStart(2, "0")
  ).join("");
}

export async function normalizeWhatsAppEvents(
  bytes: Uint8Array,
): Promise<WhatsAppEvent[]> {
  let root: ObjectValue;
  try {
    root = object(
      JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)),
    );
  } catch {
    throw invalid();
  }
  if (root.object !== "whatsapp_business_account") throw invalid();
  const result: WhatsAppEvent[] = [];
  for (const rawEntry of items(root.entry)) {
    const entry = object(rawEntry);
    const wabaId = identifier(entry.id, /^[0-9]{1,40}$/);
    for (const rawChange of items(entry.changes)) {
      const change = object(rawChange);
      if (change.field !== "messages") continue;
      const value = object(change.value);
      if (value.messaging_product !== "whatsapp") throw invalid();
      const phoneId = identifier(
        object(value.metadata).phone_number_id,
        /^[0-9]{1,40}$/,
      );
      for (const kind of ["message", "status"] as const) {
        for (
          const raw of items(
            value[kind === "message" ? "messages" : "statuses"],
          )
        ) {
          if (result.length >= 1000) {
            throw new ApiError(
              413,
              "webhook_batch_too_large",
              "Webhook batch too large",
            );
          }
          const item = object(raw);
          const messageId = identifier(item.id, /^wamid\.[^\s]{1,506}$/);
          const occurredAt = timestamp(item.timestamp);
          const phone = identifier(
            kind === "message" ? item.from : item.recipient_id,
            /^[1-9][0-9]{7,14}$/,
          );
          let payload: ObjectValue;
          if (kind === "status") {
            const status = identifier(item.status, /^[a-z_]{1,40}$/);
            if (!["sent", "delivered", "read", "failed"].includes(status)) {
              continue;
            }
            const callback =
              typeof item.biz_opaque_callback_data === "string" &&
                /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
                  .test(
                    item.biz_opaque_callback_data,
                  )
                ? item.biz_opaque_callback_data.toLowerCase()
                : null;
            const firstError = Array.isArray(item.errors)
              ? item.errors[0] as { code?: unknown } | undefined
              : undefined;
            const code = typeof firstError?.code === "number" &&
                Number.isSafeInteger(firstError.code) && firstError.code >= 0
              ? `meta_${firstError.code}`
              : null;
            payload = {
              recipient_phone: phone,
              status,
              callback,
              error_code: code,
            };
          } else {
            const type = identifier(item.type, /^[a-z_]{1,40}$/);
            if (JSON.stringify(item).length > 65536) {
              throw new ApiError(
                413,
                "webhook_message_too_large",
                "Webhook message too large",
              );
            }
            const contact = items(value.contacts).map(object).find((contact) =>
              contact.wa_id === phone
            );
            const profile =
              contact?.profile && typeof contact.profile === "object"
                ? contact.profile as ObjectValue
                : {};
            payload = {
              sender_phone: phone,
              type,
              content: item,
              contact_name: typeof profile.name === "string"
                ? profile.name.slice(0, 256)
                : phone,
            };
          }
          result.push({
            event_key: await hash([
              wabaId,
              phoneId,
              kind,
              messageId,
              ...(kind === "status" ? [payload.status, occurredAt] : []),
            ]),
            waba_id: wabaId,
            phone_number_id: phoneId,
            kind,
            message_id: messageId,
            occurred_at: occurredAt,
            payload,
          });
        }
      }
    }
  }
  return result;
}
