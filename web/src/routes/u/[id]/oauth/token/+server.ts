// Token endpoint: authorization_code (with PKCE) and refresh_token (rotating).
import { json } from "$lib/server/json";
import { OAuthError, token } from "$lib/server/oauth";
import { phone } from "$lib/server/phone";
import type { RequestHandler } from "./$types";

const NO_STORE = { pragma: "no-cache" };

export const POST: RequestHandler = async ({ params, request }) => {
  const owner = await phone(params.id);
  if (!owner) return json({ error: "invalid_request", error_description: "Unknown issuer" }, 404, NO_STORE);
  const type = request.headers.get("content-type") ?? "";
  const form = type.includes("application/json")
    ? new URLSearchParams(Object.entries((await request.json().catch(() => ({}))) as Record<string, string>))
    : new URLSearchParams(await request.text());
  try {
    return json(await token(owner.publicId, owner.userHash, form), 200, NO_STORE);
  } catch (e) {
    if (e instanceof OAuthError) return json(e.body(), e.status, NO_STORE);
    throw e;
  }
};
