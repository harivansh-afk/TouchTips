// Token endpoint: authorization_code (with PKCE) and refresh_token (rotating).
import { json } from "$lib/server/json";
import { OAuthError, token } from "$lib/server/oauth";
import { phone } from "$lib/server/phone";
import type { RequestHandler } from "./$types";

const NO_STORE = { pragma: "no-cache" };

/** A JSON body as form fields. Anything but an object of strings reads as empty, so it fails as a bad grant. */
function jsonForm(body: unknown): URLSearchParams {
  const form = new URLSearchParams();
  if (body && typeof body === "object" && !Array.isArray(body)) {
    for (const [k, v] of Object.entries(body)) if (typeof v === "string") form.set(k, v);
  }
  return form;
}

export const POST: RequestHandler = async ({ params, request }) => {
  const owner = await phone(params.id);
  if (!owner) return json({ error: "invalid_request", error_description: "Unknown issuer" }, 404, NO_STORE);
  const type = request.headers.get("content-type") ?? "";
  const form = type.includes("application/json") ? jsonForm(await request.json().catch(() => null)) : new URLSearchParams(await request.text());
  try {
    return json(await token(owner.publicId, owner.userHash, form), 200, NO_STORE);
  } catch (e) {
    if (e instanceof OAuthError) return json(e.body(), e.status, NO_STORE);
    throw e;
  }
};
