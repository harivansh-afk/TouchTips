// RFC 8414 / OpenID discovery for one phone's issuer, served at every location MCP clients look.
import type { RequestHandler } from "@sveltejs/kit";
import { json } from "./json";
import { authorizationServerMetadata } from "./oauth";
import { phone } from "./phone";

export const metadataRoute: RequestHandler = async ({ params }) => {
  const owner = await phone(params.id);
  return owner ? json(authorizationServerMetadata(owner.publicId)) : json({ error: "unknown issuer" }, 404);
};
