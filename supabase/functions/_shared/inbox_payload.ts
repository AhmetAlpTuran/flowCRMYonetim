/** A file already uploaded to Meta for this send. */
export type OutboundMedia = {
  kind: "image" | "document";
  mediaId: string;
  caption?: string | null;
  fileName?: string | null;
};

/**
 * Cloud API body for one inbox reply. Text uses the stored message body; media
 * sends the uploaded media ID with the caption (and the file name for documents),
 * never the placeholder body such as "[Fotoğraf]".
 */
export function inboxMessagePayload(
  recipient: string,
  body: string,
  callbackData: string,
  media?: OutboundMedia,
): Record<string, unknown> {
  const base = {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: recipient,
    biz_opaque_callback_data: callbackData,
  };
  if (!media) {
    return { ...base, type: "text", text: { body, preview_url: false } };
  }
  const caption = media.caption?.trim() ? media.caption.trim().slice(0, 1024) : undefined;
  if (media.kind === "image") {
    return { ...base, type: "image", image: { id: media.mediaId, ...(caption ? { caption } : {}) } };
  }
  return {
    ...base,
    type: "document",
    document: {
      id: media.mediaId,
      ...(caption ? { caption } : {}),
      ...(media.fileName ? { filename: media.fileName.slice(0, 240) } : {}),
    },
  };
}
