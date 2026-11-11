// RFC 9728: which authorization server signs clients in for this phone's MCP URL.
import { json } from "$lib/server/json";
import { protectedResourceMetadata } from "$lib/server/oauth";
import { phone } from "$lib/server/phone";
import type { RequestHandler } from "./$types";

export const GET: RequestHandler = async ({ params }) => {
  const owner = await phone(params.id);
  return owner ? json(protectedResourceMetadata(owner.publicId)) : json({ error: "unknown server" }, 404);
};
