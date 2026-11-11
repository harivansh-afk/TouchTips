// Headers every response gets, and CORS for the endpoints MCP clients call from a browser.
import type { Handle } from "@sveltejs/kit";

const CORS_PATHS = [/^\/\.well-known\/oauth-/, /^\/\.well-known\/openid-configuration/, /^\/oauth\/register$/, /^\/u\/[^/]+\/(mcp|oauth\/token|\.well-known\/)/, /^\/c\/[^/]+\/mcp$/];

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, DELETE, OPTIONS",
  "access-control-allow-headers": "authorization, content-type, accept, mcp-protocol-version, mcp-session-id, last-event-id",
  "access-control-expose-headers": "www-authenticate, mcp-session-id, mcp-protocol-version",
  "access-control-max-age": "600",
};

export const handle: Handle = async ({ event, resolve }) => {
  const cors = CORS_PATHS.some((p) => p.test(event.url.pathname));
  if (cors && event.request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  const response = await resolve(event);
  const headers = new Headers(response.headers);
  headers.set("strict-transport-security", "max-age=63072000; includeSubDomains");
  headers.set("x-content-type-options", "nosniff");
  if (cors) for (const [k, v] of Object.entries(CORS)) headers.set(k, v);
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
};
