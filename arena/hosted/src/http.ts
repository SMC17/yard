import { z } from "zod";
import { secureTokenEqual } from "./crypto";

export class HttpError extends Error {
  constructor(public readonly status: number, public readonly code: string, message: string) {
    super(message);
  }
}

export function jsonResponse(value: unknown, status = 200, extraHeaders?: HeadersInit): Response {
  const headers = new Headers(extraHeaders);
  headers.set("content-type", "application/json; charset=utf-8");
  headers.set("cache-control", "no-store");
  headers.set("x-content-type-options", "nosniff");
  return new Response(JSON.stringify(value), { status, headers });
}

export function errorResponse(error: unknown, requestId: string): Response {
  if (error instanceof HttpError) {
    return jsonResponse({ error: { code: error.code, message: error.message, request_id: requestId } }, error.status);
  }
  if (error instanceof z.ZodError) {
    return jsonResponse({
      error: {
        code: "invalid_request",
        message: "request did not match the strict schema",
        issues: error.issues.map((issue) => ({ path: issue.path.join("."), message: issue.message })),
        request_id: requestId
      }
    }, 422);
  }
  console.error(JSON.stringify({ level: "error", request_id: requestId, error: String(error) }));
  return jsonResponse({ error: { code: "internal_error", message: "request failed", request_id: requestId } }, 500);
}

export async function readJsonBounded(request: Request, maxBytes: number): Promise<unknown> {
  const contentType = request.headers.get("content-type")?.split(";", 1)[0]?.trim();
  if (contentType !== "application/json") throw new HttpError(415, "unsupported_media_type", "content-type must be application/json");
  const declared = Number(request.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > maxBytes) throw new HttpError(413, "body_too_large", "JSON body exceeds the configured limit");
  if (!request.body) throw new HttpError(400, "missing_body", "request body is required");

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel("body limit exceeded");
      throw new HttpError(413, "body_too_large", "JSON body exceeds the configured limit");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes));
  } catch {
    throw new HttpError(400, "invalid_json", "request body is not valid UTF-8 JSON");
  }
}

async function bearerToken(request: Request): Promise<string> {
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) throw new HttpError(401, "unauthorized", "bearer authorization is required");
  return authorization.slice(7);
}

export async function requireEntrant(request: Request, env: Env): Promise<void> {
  const token = await bearerToken(request);
  const entrant = await secureTokenEqual(token, env.API_BEARER_TOKEN);
  const admin = await secureTokenEqual(token, env.ADMIN_BEARER_TOKEN);
  if (!entrant && !admin) throw new HttpError(403, "forbidden", "invalid API credential");
}

export async function requireAdmin(request: Request, env: Env): Promise<void> {
  const token = await bearerToken(request);
  if (!(await secureTokenEqual(token, env.ADMIN_BEARER_TOKEN))) throw new HttpError(403, "forbidden", "admin credential is required");
}

export function parsePositiveInt(value: string, name: string): number {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) throw new Error(`${name} must be a positive integer`);
  return parsed;
}
