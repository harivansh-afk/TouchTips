// The phone already approved on the pairing sheet, so consent is accepted without another screen.
import { APIError } from "better-auth/api";
import { getAuth } from "$lib/server/auth";
import { messagePage } from "$lib/server/html";
import type { RequestHandler } from "./$types";

export const GET: RequestHandler = async ({ url, request }) => {
  try {
    const result = await getAuth().api.oauth2Consent({
      body: { accept: true, oauth_query: url.search.slice(1) },
      headers: request.headers,
    });
    const target = (result as { url?: string })?.url;
    if (target) return Response.redirect(target, 302);
  } catch (error) {
    const text = error instanceof APIError ? error.message : "Could not finish connecting.";
    return messagePage("Can't connect", text);
  }
  return messagePage("Can't connect", "Could not finish connecting.");
};
