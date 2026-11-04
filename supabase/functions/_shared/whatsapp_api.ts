import { ApiError, metaId } from "./http.ts";
import { uploadSessionPath } from "./template_submission.ts";

export class GraphApiError extends ApiError {
  constructor(
    readonly httpStatus: number,
    readonly providerCode: number | null,
  ) {
    super(502, "whatsapp_rejected", "WhatsApp rejected the request");
  }
}

export class WhatsAppApi {
  constructor(
    readonly version: string,
    readonly accessToken: string,
    private readonly transport: typeof fetch = fetch,
  ) {
    if (!/^v[0-9]+\.[0-9]+$/.test(version)) {
      throw new ApiError(
        503,
        "graph_version_missing",
        "WhatsApp API version must be configured",
      );
    }
  }

  async request(
    path: string,
    method = "GET",
    body?: unknown,
    query: Record<string, string> = {},
  ): Promise<Response> {
    // Endpoint paths are constructed by server code from validated IDs. Neither
    // caller-provided hosts nor provider paging URLs are followed.
    if (!/^(debug_token|[0-9]+(?:\/[a-z_]+)?)$/.test(path)) {
      throw new Error("Invalid Graph path");
    }
    const url = new URL(`https://graph.facebook.com/${this.version}/${path}`);
    for (const [key, value] of Object.entries(query)) {
      url.searchParams.set(key, value);
    }
    try {
      return await this.transport(url, {
        method,
        headers: {
          Authorization: `Bearer ${this.accessToken}`,
          "Content-Type": "application/json",
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        redirect: "error",
        signal: AbortSignal.timeout(15000),
      });
    } catch {
      throw new ApiError(
        503,
        "whatsapp_transport",
        "WhatsApp response unavailable",
      );
    }
  }

  async data(
    path: string,
    method = "GET",
    body?: unknown,
    query: Record<string, string> = {},
  ): Promise<Record<string, unknown>> {
    const response = await this.request(path, method, body, query);
    const result: unknown = await response.json().catch(() => null);
    if (!result || typeof result !== "object" || Array.isArray(result)) {
      throw new ApiError(
        502,
        "whatsapp_invalid_response",
        "WhatsApp response unavailable",
      );
    }
    const data = result as Record<string, unknown>;
    if (!response.ok || data.error) {
      const error = data.error as { code?: unknown } | undefined;
      throw new GraphApiError(
        response.status,
        typeof error?.code === "number" ? error.code : null,
      );
    }
    return data;
  }

  // Resumable Upload API: returns the header handle used in template examples.
  // The session belongs to this SaaS's Meta app; the tenant token authorizes it.
  async uploadTemplateMedia(
    appId: string,
    media: { fileName: string; mimeType: string; bytes: Uint8Array<ArrayBuffer> },
  ): Promise<string> {
    const session = await this.data(`${metaId(appId)}/uploads`, "POST", undefined, {
      file_name: media.fileName,
      file_length: String(media.bytes.length),
      file_type: media.mimeType,
    });
    const sessionPath = uploadSessionPath(session.id);
    let response: Response;
    try {
      response = await this.transport(
        `https://graph.facebook.com/${this.version}/${sessionPath}`,
        {
          method: "POST",
          headers: {
            Authorization: `OAuth ${this.accessToken}`,
            file_offset: "0",
            "Content-Type": "application/octet-stream",
          },
          body: media.bytes,
          redirect: "error",
          signal: AbortSignal.timeout(60000),
        },
      );
    } catch {
      throw new ApiError(503, "whatsapp_transport", "WhatsApp response unavailable");
    }
    const result: unknown = await response.json().catch(() => null);
    const data = result && typeof result === "object" && !Array.isArray(result)
      ? result as Record<string, unknown>
      : null;
    if (!response.ok || !data || data.error) {
      const error = data?.error as { code?: unknown } | undefined;
      throw new GraphApiError(
        response.status,
        typeof error?.code === "number" ? error.code : null,
      );
    }
    if (typeof data.h !== "string" || !data.h || data.h.length > 4096) {
      throw new ApiError(502, "whatsapp_invalid_response", "WhatsApp upload handle unavailable");
    }
    return data.h;
  }

  async findPhone(
    wabaId: string,
    phoneId: string,
  ): Promise<{ display_phone_number: string; verified_name: string }> {
    metaId(wabaId);
    metaId(phoneId);
    let after = "";
    const deadline = Date.now() + 30000;
    for (let page = 0; page < 20; page++) {
      if (Date.now() >= deadline) {
        throw new ApiError(
          503,
          "phone_lookup_incomplete",
          "Phone lookup timed out; retry later",
        );
      }
      const result = await this.data(
        `${wabaId}/phone_numbers`,
        "GET",
        undefined,
        {
          fields: "id,display_phone_number,verified_name",
          limit: "100",
          ...(after ? { after } : {}),
        },
      );
      const phones = Array.isArray(result.data)
        ? result.data as Record<string, unknown>[]
        : [];
      const phone = phones.find((value) => value?.id === phoneId);
      if (phone && typeof phone.display_phone_number === "string") {
        return {
          display_phone_number: phone.display_phone_number.slice(0, 100),
          verified_name: typeof phone.verified_name === "string"
            ? phone.verified_name.slice(0, 256)
            : "",
        };
      }
      const paging = result.paging as {
        next?: unknown;
        cursors?: { after?: unknown };
      } | undefined;
      const next = paging?.cursors?.after;
      if (!paging?.next) break;
      if (typeof next !== "string" || !next || next === after || page === 19) {
        throw new ApiError(
          503,
          "phone_lookup_incomplete",
          "Phone lookup could not be completed",
        );
      }
      after = next;
    }
    throw new ApiError(
      422,
      "phone_account_mismatch",
      "Phone number was not found in the selected WhatsApp account",
    );
  }
}

export async function verifyConnectionToken(
  version: string,
  token: string,
  appId: string,
  appSecret: string,
  transport: typeof fetch = fetch,
): Promise<string | null> {
  const inspector = new WhatsAppApi(
    version,
    `${metaId(appId)}|${appSecret}`,
    transport,
  );
  const response = await inspector.data("debug_token", "GET", undefined, {
    input_token: token,
  });
  const data = response.data as Record<string, unknown> | undefined;
  if (
    !data || data.is_valid !== true || data.app_id !== appId ||
    !Array.isArray(data.scopes) ||
    !data.scopes.includes("whatsapp_business_management") ||
    !data.scopes.includes("whatsapp_business_messaging")
  ) {
    throw new ApiError(
      422,
      "invalid_whatsapp_token",
      "Token must belong to this application and grant WhatsApp management and messaging access",
    );
  }
  if (
    typeof data.expires_at !== "number" || !Number.isFinite(data.expires_at) ||
    data.expires_at < 0
  ) {
    throw new ApiError(
      422,
      "token_expiry_unknown",
      "Token expiry could not be verified",
    );
  }
  if (
    data.data_access_expires_at !== undefined &&
    (typeof data.data_access_expires_at !== "number" ||
      !Number.isFinite(data.data_access_expires_at) ||
      data.data_access_expires_at < 0)
  ) {
    throw new ApiError(
      422,
      "token_expiry_unknown",
      "Token expiry could not be verified",
    );
  }
  const expiries = [data.expires_at, data.data_access_expires_at]
    .filter((value): value is number => typeof value === "number" && value > 0);
  if (expiries.length === 0) return null;
  const expiry = Math.min(...expiries) * 1000;
  if (
    !Number.isFinite(expiry) || expiry <= Date.now() + 120000 ||
    expiry > 8640000000000000
  ) {
    throw new ApiError(
      422,
      "token_expired",
      "Token has expired or is about to expire",
    );
  }
  return new Date(expiry).toISOString();
}
