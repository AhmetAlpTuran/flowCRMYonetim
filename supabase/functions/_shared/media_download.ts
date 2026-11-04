import { ApiError, readBytes } from "./http.ts";
import { GraphApiError, type WhatsAppApi } from "./whatsapp_api.ts";

/** Stored media is capped; larger files stay in WhatsApp and are marked too_large. */
export const MAX_MEDIA_BYTES = 25 * 1024 * 1024;

export class MediaTooLargeError extends Error {
  constructor() {
    super("Media exceeds the storage limit");
  }
}

export type DownloadedMedia = {
  bytes: Uint8Array<ArrayBuffer>;
  mimeType: string;
};

const EXTENSIONS: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "video/mp4": "mp4",
  "video/3gpp": "3gp",
  "audio/ogg": "ogg",
  "audio/mpeg": "mp3",
  "audio/mp4": "m4a",
  "audio/aac": "aac",
  "audio/amr": "amr",
  "application/pdf": "pdf",
  "text/plain": "txt",
};

export function mediaExtension(mimeType: string): string {
  return EXTENSIONS[mimeType.split(";")[0].trim().toLowerCase()] ?? "bin";
}

/** The token is only ever sent to Meta's media hosts over HTTPS. */
export function isMetaMediaUrl(value: unknown): value is string {
  if (typeof value !== "string" || value.length > 4096) return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && url.username === "" && url.password === "" &&
      (url.hostname === "lookaside.fbsbx.com" || url.hostname.endsWith(".fbsbx.com") ||
        url.hostname.endsWith(".whatsapp.net"));
  } catch {
    return false;
  }
}

/**
 * Resolves a WhatsApp media ID with the tenant's token and downloads it.
 * Meta's download URLs expire after a few minutes; the media ID stays valid for
 * about 30 days, so a failed attempt is retried from the ID.
 */
export async function downloadWhatsAppMedia(
  api: WhatsAppApi,
  mediaId: string,
  transport: typeof fetch = fetch,
  maxBytes = MAX_MEDIA_BYTES,
): Promise<DownloadedMedia> {
  if (!/^[0-9]{1,40}$/.test(mediaId)) {
    throw new ApiError(400, "invalid_media_id", "Invalid media ID");
  }
  const meta = await api.data(mediaId, "GET");
  const declared = typeof meta.file_size === "number" ? meta.file_size : null;
  if (declared !== null && declared > maxBytes) throw new MediaTooLargeError();
  if (!isMetaMediaUrl(meta.url)) {
    throw new ApiError(502, "whatsapp_invalid_response", "Media URL unavailable");
  }
  let response: Response;
  try {
    response = await transport(meta.url, {
      headers: { Authorization: `Bearer ${api.accessToken}` },
      redirect: "error",
      signal: AbortSignal.timeout(60000),
    });
  } catch {
    throw new ApiError(503, "whatsapp_transport", "Media download unavailable");
  }
  if (!response.ok) {
    throw new GraphApiError(response.status, null);
  }
  let bytes: Uint8Array<ArrayBuffer>;
  try {
    bytes = await readBytes(response, maxBytes, 60000);
  } catch (error) {
    if (error instanceof ApiError && error.code === "request_too_large") {
      throw new MediaTooLargeError();
    }
    throw new ApiError(503, "whatsapp_transport", "Media download incomplete");
  }
  if (declared !== null && bytes.length !== declared) {
    throw new ApiError(502, "media_size_mismatch", "Media download incomplete");
  }
  const mimeType = typeof meta.mime_type === "string" && meta.mime_type.length <= 100
    ? meta.mime_type.split(";")[0].trim().toLowerCase()
    : (response.headers.get("content-type") ?? "application/octet-stream").split(";")[0];
  return { bytes, mimeType };
}
