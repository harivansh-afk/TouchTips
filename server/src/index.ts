// One Worker: OAuth authorization server, MCP resource, and the phone's sync API.
import { OAuthProvider } from "@cloudflare/workers-oauth-provider";
import { env as moduleEnv } from "cloudflare:workers";
import { deleteAccount, listClients, putSnapshotRoute, revokeClient } from "./api";
import { userIdFromRequest } from "./auth";
import { SCOPE, type Env } from "./env";
import { mcpHandler } from "./mcp";
import {
  appleAppSiteAssociation,
  authorize,
  pairApprove,
  pairDeny,
  pairInfo,
  pairLanding,
  pairStatus,
  personLanding,
} from "./pair";

const PUBLIC_URL = (moduleEnv as unknown as Env).PUBLIC_URL;
const DAY = 24 * 60 * 60;

const defaultHandler: ExportedHandler<Env> = {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    if (path === "/authorize" && method === "GET") return authorize(request, env);
    if (path === "/.well-known/apple-app-site-association") return appleAppSiteAssociation();
    if (path === "/" || path === "/connect") return Response.redirect("https://touchtips.app/connect", 302);

    let m: RegExpExecArray | null;
    if ((m = /^\/pair\/(\d{6})\/status$/.exec(path)) && method === "GET") return pairStatus(env, m[1]);
    if ((m = /^\/pair\/(\d{6})$/.exec(path)) && method === "GET") return pairLanding();
    if (/^\/p\/[^/]+$/.test(path) && method === "GET") return personLanding();

    if (path.startsWith("/v1/")) {
      const userId = await userIdFromRequest(request);
      if (!userId) return new Response(JSON.stringify({ error: "device key required" }), { status: 401, headers: { "content-type": "application/json" } });
      if (path === "/v1/snapshot" && method === "PUT") return putSnapshotRoute(request, env, userId);
      if (path === "/v1/account" && method === "DELETE") return deleteAccount(env, userId);
      if (path === "/v1/clients" && method === "GET") return listClients(env, userId);
      if ((m = /^\/v1\/clients\/([^/]+)$/.exec(path)) && method === "DELETE") return revokeClient(env, userId, decodeURIComponent(m[1]));
      if ((m = /^\/v1\/pair\/(\d{6})$/.exec(path)) && method === "GET") return pairInfo(env, m[1]);
      if ((m = /^\/v1\/pair\/(\d{6})\/approve$/.exec(path)) && method === "POST") return pairApprove(env, m[1], userId);
      if ((m = /^\/v1\/pair\/(\d{6})\/deny$/.exec(path)) && method === "POST") return pairDeny(env, m[1]);
    }
    return new Response("Not found", { status: 404 });
  },
};

export default new OAuthProvider<Env>({
  apiRoute: "/mcp",
  apiHandler: { fetch: (request, env, ctx) => mcpHandler(request, env, ctx) },
  defaultHandler,
  authorizeEndpoint: "/authorize",
  tokenEndpoint: "/oauth/token",
  clientRegistrationEndpoint: "/oauth/register",
  clientIdMetadataDocumentEnabled: true,
  scopesSupported: [SCOPE],
  requiredScopes: [SCOPE],
  resourceMetadata: {
    resource: `${PUBLIC_URL}/mcp`,
    authorization_servers: [PUBLIC_URL],
  },
  accessTokenTTL: 60 * 60,
  // A paired client keeps working as long as it is used at least once every 90 days.
  refreshTokenTTL: 365 * DAY,
  refreshTokenIdleTTL: 90 * DAY,
});
