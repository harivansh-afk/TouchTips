import { getAuth } from "$lib/server/auth";
import { building } from "$app/environment";
import type { Handle } from "@sveltejs/kit";

// Better Auth owns /api/auth/* plus the OAuth discovery documents at the well-known root.
// Everything else, including prerendered pages, never touches it.
export const handle: Handle = async ({ event, resolve }) => {
  if (building) return resolve(event);
  const path = event.url.pathname;
  if (path.startsWith("/api/auth/") || path.startsWith("/.well-known/oauth-") || path === "/.well-known/jwks.json") {
    return getAuth().handler(event.request);
  }
  return resolve(event);
};
