// RFC 7591 dynamic client registration. Public clients only.
import { json } from "$lib/server/json";
import { OAuthError, registerClient } from "$lib/server/oauth";
import type { RequestHandler } from "./$types";

export const POST: RequestHandler = async ({ request }) => {
  const raw = await request.text();
  if (raw.length > 20_000) return json({ error: "invalid_client_metadata", error_description: "Too large" }, 400);
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ error: "invalid_client_metadata", error_description: "Body must be JSON" }, 400);
  }
  try {
    return json(await registerClient(body), 201);
  } catch (e) {
    if (e instanceof OAuthError) return json(e.body(), e.status);
    throw e;
  }
};
