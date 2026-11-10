import { requireMcpAuth } from "@better-auth/mcp";
import { MCP_RESOURCE, SCOPE, getAuth } from "$lib/server/auth";
import { hashForUserId } from "$lib/server/identity";
import { mcpHandlerFor } from "$lib/server/mcp";
import type { RequestHandler } from "./$types";

let protectedHandler: ((request: Request) => Promise<Response>) | undefined;

const buildHandler = () => requireMcpAuth(
  getAuth(),
  async (request, claims) => {
    const userHash = typeof claims.sub === "string" ? await hashForUserId(claims.sub) : null;
    if (!userHash) return new Response("Unknown user", { status: 403 });
    return mcpHandlerFor(userHash).fetch(request);
  },
  { resource: MCP_RESOURCE, requiredScopes: [SCOPE] },
);

const handle: RequestHandler = ({ request }) => (protectedHandler ??= buildHandler())(request);
export const POST = handle;
export const GET = handle;
export const DELETE = handle;
