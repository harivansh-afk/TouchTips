// One phone's MCP server. OAuth bearer tokens only; a 401 points the client at the metadata to sign in.
import { readSnapshot } from "$lib/server/account";
import { json } from "$lib/server/json";
import { mcpHandlerFor } from "$lib/server/mcp";
import { openAccessToken, protectedResourceMetadataUrl, SCOPE } from "$lib/server/oauth";
import { phone } from "$lib/server/phone";
import type { RequestHandler } from "./$types";

const handle: RequestHandler = async ({ params, request }) => {
  const owner = await phone(params.id);
  if (!owner) return json({ error: "unknown server" }, 404);
  const bearer = /^Bearer\s+([A-Za-z0-9_-]{43})$/.exec(request.headers.get("authorization") ?? "")?.[1];
  const opened = bearer ? await openAccessToken(owner.userHash, bearer) : null;
  if (!opened) {
    const error = request.headers.has("authorization") ? `, error="invalid_token"` : "";
    return json({ error: "unauthorized" }, 401, {
      "www-authenticate": `Bearer resource_metadata="${protectedResourceMetadataUrl(owner.publicId)}", scope="${SCOPE}"${error}`,
    });
  }
  return mcpHandlerFor(() => readSnapshot(owner.userHash, opened.dataKey)).fetch(request);
};

export const POST = handle;
export const GET = handle;
export const DELETE = handle;
