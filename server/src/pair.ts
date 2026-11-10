// OAuth consent, done as device pairing: the browser shows a code, the phone approves it.
import { AuthorizationError, authorizationErrorRedirect, type AuthRequest } from "@cloudflare/workers-oauth-provider";
import { APPLE_APP_ID, SCOPE, type Env, type Props } from "./env";
import { messagePage, pairingPage } from "./html";
import { createPairing, finishPairing, getPairing, purgePairings } from "./store";

export const APP_STORE_URL = "https://touchtips.app/ios";

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

/** GET /authorize — the OAuth client sent the user here. */
export async function authorize(request: Request, env: Env): Promise<Response> {
  let authRequest: AuthRequest;
  try {
    authRequest = await env.OAUTH_PROVIDER.parseAuthRequest(request);
  } catch (error) {
    if (error instanceof AuthorizationError && error.redirectTo) return Response.redirect(error.redirectTo, 302);
    const text = error instanceof AuthorizationError ? error.description : "This app could not be verified.";
    return messagePage("Can't connect", text);
  }
  const client = await env.OAUTH_PROVIDER.lookupClient(authRequest.clientId);
  const clientName = client?.clientName?.trim() || "this app";
  const code = await createPairing(env, authRequest, clientName);
  const openUrl = `${env.PUBLIC_URL}/pair/${code}`;
  if (request.headers.get("accept")?.includes("application/json")) {
    return json({ code, clientName, openUrl });
  }
  return pairingPage({ code, clientName, openUrl, appStoreUrl: APP_STORE_URL });
}

/** GET /pair/:code/status — polled by the browser. */
export async function pairStatus(env: Env, code: string): Promise<Response> {
  const row = await getPairing(env, code);
  if (!row) return json({ status: "expired" });
  if (row.status === "pending") return json({ status: "pending" });
  return json({ status: row.status, redirectTo: row.redirect_to });
}

/** GET /pair/:code — the universal link. Reached in a browser only when the app isn't installed. */
export function pairLanding(): Response {
  return messagePage(
    "Get TouchTips",
    "Install TouchTips, then come back to this page and tap the link again.",
    { href: APP_STORE_URL, label: "App Store" },
  );
}

/** GET /v1/pair/:code — the app asks what it is about to approve. Needs the device key. */
export async function pairInfo(env: Env, code: string): Promise<Response> {
  const row = await getPairing(env, code);
  if (!row || row.status !== "pending") return json({ error: "unknown or expired code" }, 404);
  return json({ clientName: row.client_name, scope: [SCOPE] });
}

/** POST /v1/pair/:code/approve — the phone, holding the device key, grants the client access. */
export async function pairApprove(env: Env, code: string, userId: string): Promise<Response> {
  const row = await getPairing(env, code);
  if (!row || row.status !== "pending") return json({ error: "unknown or expired code" }, 404);
  const authRequest = JSON.parse(row.auth_request) as AuthRequest;
  const props: Props = { userId };
  const { redirectTo } = await env.OAUTH_PROVIDER.completeAuthorization({
    request: authRequest,
    userId,
    metadata: { clientName: row.client_name, pairedAt: new Date().toISOString() },
    scope: [SCOPE],
    props,
  });
  await finishPairing(env, code, "approved", redirectTo);
  void purgePairings(env);
  return json({ clientName: row.client_name });
}

/** POST /v1/pair/:code/deny — the phone said no; send the client an access_denied error. */
export async function pairDeny(env: Env, code: string): Promise<Response> {
  const row = await getPairing(env, code);
  if (!row || row.status !== "pending") return json({ error: "unknown or expired code" }, 404);
  const authRequest = JSON.parse(row.auth_request) as AuthRequest;
  const redirectTo = authorizationErrorRedirect(authRequest, "access_denied", "The user declined in TouchTips.");
  await finishPairing(env, code, "denied", redirectTo);
  return json({ ok: true });
}

/** GET /.well-known/apple-app-site-association — lets iOS open /pair/* and /p/* in the app. */
export function appleAppSiteAssociation(): Response {
  const body = {
    applinks: {
      details: [{ appIDs: [APPLE_APP_ID], components: [{ "/": "/pair/*" }, { "/": "/p/*" }] }],
    },
  };
  return new Response(JSON.stringify(body), { headers: { "content-type": "application/json" } });
}

/** GET /p/:id — a person link opened outside the app. */
export function personLanding(): Response {
  return messagePage("Open in TouchTips", "This link opens a person in TouchTips on your iPhone.", {
    href: APP_STORE_URL,
    label: "Get TouchTips",
  });
}
