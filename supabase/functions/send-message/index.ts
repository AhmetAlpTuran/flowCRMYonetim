import {
  ApiError,
  endpoint,
  jsonResponse,
  readJson,
  uuid,
} from "../_shared/http.ts";
import { authenticate } from "../_shared/supabase.ts";

// The authenticated RPC validates tenant, employee, channel, content and window.
// Provider sending is owned exclusively by inbox-worker.
Deno.serve(endpoint(async (req) => {
  const { client } = await authenticate(req);
  const body = await readJson(req, 65536);
  const tenantId = uuid(body.tenant_id, "Tenant ID");
  const conversationId = uuid(body.conversation_id, "Conversation ID");
  const messageId = uuid(body.message_id, "Message ID");
  const media = body.media;
  if (media !== undefined && (typeof media !== "object" || media === null || Array.isArray(media))) {
    throw new ApiError(422, "invalid_media", "Media must be an object");
  }
  if (typeof body.body !== "string" && media === undefined) {
    throw new ApiError(422, "invalid_message", "Message text required");
  }
  const m = media as Record<string, unknown> | undefined;
  const text = (value: unknown) => typeof value === "string" ? value : null;
  const { data, error } = m
    ? await client.rpc("enqueue_inbox_media_message", {
      p_tenant_id: tenantId,
      p_conversation_id: conversationId,
      p_message_id: messageId,
      p_storage_path: text(m.storage_path),
      p_kind: text(m.kind),
      p_mime_type: text(m.mime_type),
      p_file_name: text(m.file_name),
      p_caption: text(body.body),
    })
    : await client.rpc("enqueue_inbox_message", {
      p_tenant_id: tenantId,
      p_conversation_id: conversationId,
      p_message_id: messageId,
      p_body: body.body,
    });
  if (error) {
    const errors: Record<string, [number, string, string]> = {
      "42501": [403, "forbidden", "Inbox permission required"],
      "P0002": [404, "conversation_unavailable", "Conversation unavailable"],
      "P0003": [
        409,
        "conversation_unmapped",
        "Map this conversation to a WhatsApp account",
      ],
      "P0004": [
        409,
        "customer_service_window_closed",
        "Use an approved template outside the customer service window",
      ],
      "P0005": [
        409,
        "connection_unavailable",
        "Reconnect the WhatsApp account",
      ],
      "P0007": [
        409,
        "conversation_closed",
        "Reopen the conversation before replying",
      ],
      "P0008": [
        409,
        "conversation_assigned_elsewhere",
        "Claim the conversation before replying",
      ],
      "40001": [
        409,
        "message_identity_conflict",
        "Message identity already used",
      ],
      "22023": [
        422,
        "invalid_message",
        "Text must contain 1 to 4096 characters",
      ],
      "P0009": [
        422,
        "invalid_media",
        "Upload a JPEG/PNG image up to 5 MB or a document up to 16 MB",
      ],
    };
    const known = errors[error.code];
    if (known) throw new ApiError(...known);
    throw new ApiError(
      503,
      "enqueue_unconfirmed",
      "Message queue result unavailable",
    );
  }
  return jsonResponse(data, 202);
}));
