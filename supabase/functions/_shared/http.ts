export class ApiError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) {
    super(message);
    this.name = "ApiError";
  }
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

export function endpoint(handler: (req: Request) => Promise<Response>) {
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
    if (req.method !== "POST") {
      return jsonResponse({
        error: "Method not allowed",
        code: "method_not_allowed",
      }, 405);
    }
    try {
      return await handler(req);
    } catch (error) {
      return errorResponse(error);
    }
  };
}

export function errorResponse(error: unknown): Response {
  const requestId = crypto.randomUUID();
  const known = error instanceof ApiError;
  // Never log bodies, tokens, provider URLs or raw fetch/database errors.
  console.error(
    JSON.stringify({
      request_id: requestId,
      code: known ? error.code : "internal_error",
    }),
  );
  return jsonResponse({
    code: known ? error.code : "internal_error",
    error: known ? error.message : "Operation unavailable",
    request_id: requestId,
  }, known ? error.status : 500);
}

export async function readJson(
  req: Request,
  maxBytes = 65536,
): Promise<Record<string, unknown>> {
  if (
    !req.headers.get("Content-Type")?.toLowerCase().startsWith(
      "application/json",
    )
  ) {
    throw new ApiError(415, "invalid_content_type", "JSON request required");
  }
  const bytes = await readBytes(req, maxBytes);
  let parsed: unknown;
  try {
    parsed = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(bytes),
    );
  } catch {
    throw new ApiError(400, "invalid_json", "JSON object required");
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new ApiError(400, "invalid_json", "JSON object required");
  }
  return parsed as Record<string, unknown>;
}

export async function readBytes(
  req: Request | Response,
  maxBytes: number,
  timeoutMs = 10000,
): Promise<Uint8Array<ArrayBuffer>> {
  const reader = req.body?.getReader();
  if (!reader) throw new ApiError(400, "invalid_json", "JSON object required");
  let size = 0;
  const chunks: Uint8Array[] = [];
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, reject) => {
    timer = setTimeout(
      () =>
        reject(
          new ApiError(408, "request_body_timeout", "Request body timed out"),
        ),
      timeoutMs,
    );
  });
  try {
    while (true) {
      const { value, done } = await Promise.race([reader.read(), deadline]);
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) {
        throw new ApiError(413, "request_too_large", "Request too large");
      }
      chunks.push(value);
    }
  } catch (error) {
    void reader.cancel().catch(() => {});
    throw error;
  } finally {
    clearTimeout(timer);
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return bytes;
}

export function uuid(value: unknown, label: string): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      value,
    )
  ) {
    throw new ApiError(400, "invalid_id", `${label} required`);
  }
  return value.toLowerCase();
}

export function metaId(value: unknown): string {
  if (typeof value !== "string" || !/^[0-9]{1,40}$/.test(value)) {
    throw new ApiError(
      400,
      "invalid_meta_id",
      "Valid WhatsApp account and phone IDs required",
    );
  }
  return value;
}
