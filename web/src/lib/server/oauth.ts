// OAuth 2.1 for MCP clients, per the MCP authorization spec: protected resource metadata (RFC 9728),
// authorization server metadata (RFC 8414), dynamic client registration (RFC 7591), PKCE S256 only,
// resource indicators (RFC 8707), issuer in the response (RFC 9207), rotating refresh tokens.
//
// Each phone is its own issuer: https://touchtips.app/u/<public id>. There is no sign-in page. The phone
// approves: a push asks "Allow Claude?", and Allow sends the device key, which unwraps the data key.
import { BASE_URL } from "./config";
import { query } from "./db";
import { newId, openForServer, pkceMatches, sealForServer, secret, sha256, unwrap, wrap } from "./crypto";
import type { Account } from "./account";
import { pushApproval } from "./apns";
import { asClient, clientName, OAUTH_CLIENTS, type Client } from "./store";

export const SCOPE = "read";
const ACCESS_SECONDS = 60 * 60;
const REFRESH_DAYS = 60;
const REQUEST_MINUTES = 10;
const CODE_MINUTES = 5;
const MAX_PENDING = 10;

export function issuer(publicId: string): string {
  return `${BASE_URL}/u/${publicId}`;
}

export function resourceUrl(publicId: string): string {
  return `${issuer(publicId)}/mcp`;
}

export function protectedResourceMetadataUrl(publicId: string): string {
  return `${BASE_URL}/.well-known/oauth-protected-resource/u/${publicId}/mcp`;
}

export function protectedResourceMetadata(publicId: string) {
  return {
    resource: resourceUrl(publicId),
    authorization_servers: [issuer(publicId)],
    scopes_supported: [SCOPE],
    bearer_methods_supported: ["header"],
    resource_name: "TouchTips",
  };
}

export function authorizationServerMetadata(publicId: string) {
  const base = issuer(publicId);
  return {
    issuer: base,
    authorization_endpoint: `${base}/oauth/authorize`,
    token_endpoint: `${base}/oauth/token`,
    registration_endpoint: `${BASE_URL}/oauth/register`,
    scopes_supported: [SCOPE],
    response_types_supported: ["code"],
    response_modes_supported: ["query"],
    grant_types_supported: ["authorization_code", "refresh_token"],
    token_endpoint_auth_methods_supported: ["none"],
    code_challenge_methods_supported: ["S256"],
    authorization_response_iss_parameter_supported: true,
  };
}

// MARK: - Registration

export class OAuthError extends Error {
  constructor(
    readonly code: string,
    readonly description: string,
    readonly status = 400,
  ) {
    super(description);
  }
  body() {
    return { error: this.code, error_description: this.description };
  }
}

const BLOCKED_SCHEMES = new Set(["javascript:", "data:", "vbscript:", "file:", "about:", "blob:", "ftp:", "ws:", "wss:"]);

/** https anywhere, http only to this machine (RFC 8252 loopback), or an app's own scheme. Never a fragment. */
export function redirectAllowed(uri: string): boolean {
  if (uri.length > 2000) return false;
  let url: URL;
  try {
    url = new URL(uri);
  } catch {
    return false;
  }
  if (url.hash || url.username || url.password) return false;
  if (url.protocol === "https:") return true;
  if (url.protocol === "http:") return ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  return /^[a-z][a-z0-9+.-]*:$/.test(url.protocol) && !BLOCKED_SCHEMES.has(url.protocol);
}

function cleanName(value: unknown): string {
  const name = typeof value === "string" ? value.replace(/[\p{C}<>]/gu, "").trim().slice(0, 60) : "";
  return name || "An MCP client";
}

export async function registerClient(body: unknown) {
  const meta = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
  const uris = meta.redirect_uris;
  if (!Array.isArray(uris) || uris.length === 0 || uris.length > 10) {
    throw new OAuthError("invalid_redirect_uri", "redirect_uris must list 1 to 10 URIs");
  }
  if (!uris.every((u) => typeof u === "string" && redirectAllowed(u))) {
    throw new OAuthError("invalid_redirect_uri", "Each redirect URI must be https, http to localhost, or an app scheme, with no fragment");
  }
  const clientId = newId("c_");
  const name = cleanName(meta.client_name);
  await query("INSERT INTO oauth_client (client_id, client_name, redirect_uris) VALUES ($1, $2, $3)", [clientId, name, uris]);
  return {
    client_id: clientId,
    client_id_issued_at: Math.floor(Date.now() / 1000),
    client_name: name,
    redirect_uris: uris,
    grant_types: ["authorization_code", "refresh_token"],
    response_types: ["code"],
    token_endpoint_auth_method: "none",
    scope: SCOPE,
  };
}

// MARK: - Authorize

/** Where each client's sign-in returns to. A match means the prompt can name the client; otherwise it shows the host. */
const KNOWN_HOSTS: Partial<Record<Client, string[]>> = {
  claude: ["claude.ai", "claude.com"],
  chatgpt: ["chatgpt.com", "openai.com"],
  grok: ["cursor.com", "x.ai"],
};

function isLoopback(url: URL): boolean {
  return url.protocol === "http:" && ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
}

/** What the phone shows: "Claude", or "Some Name · evil.example" when the redirect isn't one we know for that client. */
export function displayName(windowClient: Client | null, registeredName: string, redirectUri: string): string {
  const url = new URL(redirectUri);
  if (isLoopback(url)) return registeredName.length > 40 ? `${registeredName.slice(0, 40)}…` : registeredName;
  const host = url.protocol === "https:" ? url.hostname : url.protocol.slice(0, -1);
  const known = windowClient ? KNOWN_HOSTS[windowClient] : undefined;
  if (known?.some((h) => host === h || host.endsWith(`.${h}`))) return clientName(windowClient!);
  return `${registeredName.slice(0, 40)} · ${host}`;
}

export type AuthorizeOutcome =
  | { kind: "error"; message: string }
  | { kind: "redirect"; location: string }
  | { kind: "wait"; requestId: string; browserSecret: string; displayName: string; pushed: boolean };

function errorRedirect(redirectUri: string, publicId: string, error: string, state: string | null, description?: string): AuthorizeOutcome {
  const url = new URL(redirectUri);
  url.searchParams.set("error", error);
  if (description) url.searchParams.set("error_description", description);
  if (state) url.searchParams.set("state", state);
  url.searchParams.set("iss", issuer(publicId));
  return { kind: "redirect", location: url.toString() };
}

function sameResource(given: string, publicId: string): boolean {
  return given.replace(/\/$/, "") === resourceUrl(publicId);
}

export async function authorize(publicId: string, userHash: string, params: URLSearchParams): Promise<AuthorizeOutcome> {
  const clientId = params.get("client_id") ?? "";
  const client = (
    await query<{ client_name: string; redirect_uris: string[] }>("SELECT client_name, redirect_uris FROM oauth_client WHERE client_id = $1", [
      clientId,
    ])
  )[0];
  if (!client) return { kind: "error", message: "This app isn't registered with TouchTips. Remove the connector and add it again." };
  const given = params.get("redirect_uri");
  const redirectUri = given ?? (client.redirect_uris.length === 1 ? client.redirect_uris[0] : null);
  if (!redirectUri || !client.redirect_uris.includes(redirectUri)) {
    return { kind: "error", message: "This sign-in link doesn't match the app that registered it." };
  }
  // From here on, errors go back to the client.
  const state = params.get("state");
  if (params.get("response_type") !== "code") return errorRedirect(redirectUri, publicId, "unsupported_response_type", state);
  const challenge = params.get("code_challenge") ?? "";
  if (params.get("code_challenge_method") !== "S256" || !/^[A-Za-z0-9_-]{43}$/.test(challenge)) {
    return errorRedirect(redirectUri, publicId, "invalid_request", state, "PKCE with S256 is required");
  }
  const resource = params.get("resource");
  if (resource && !sameResource(resource, publicId)) return errorRedirect(redirectUri, publicId, "invalid_target", state);
  const scope = params.get("scope");
  if (scope && !scope.split(" ").filter(Boolean).every((s) => s === SCOPE)) {
    return errorRedirect(redirectUri, publicId, "invalid_scope", state, `Only "${SCOPE}" is offered`);
  }

  const account = (
    await query<{ window_client: string | null; window_open: boolean; apns_token: string | null; apns_env: "sandbox" | "production" | null }>(
      `SELECT window_client, window_until > now() AS window_open, apns_token, apns_env FROM account WHERE user_hash = $1`,
      [userHash],
    )
  )[0];
  const pending = await query<{ n: number }>(
    "SELECT count(*)::int AS n FROM auth_request WHERE user_hash = $1 AND status = 'pending' AND expires_at > now()",
    [userHash],
  );
  if (pending[0].n >= MAX_PENDING) return { kind: "error", message: "Too many sign-in attempts. Try again in a few minutes." };

  const windowClient = account?.window_open ? asClient(account.window_client) : null;
  const name = displayName(windowClient, client.client_name, redirectUri);
  const requestId = newId("r_");
  const browserSecret = secret();
  await query(
    `INSERT INTO auth_request (id, user_hash, client_id, client, display_name, redirect_uri, state, code_challenge, browser_hash, expires_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now() + make_interval(mins => $10))`,
    [requestId, userHash, clientId, windowClient ?? "other", name, redirectUri, state, challenge, sha256(browserSecret), REQUEST_MINUTES],
  );

  // A prompt only while the user is connecting from the app, so nobody else can make the phone ask.
  let pushed = false;
  if (windowClient && OAUTH_CLIENTS.includes(windowClient) && account?.apns_token && account.apns_env) {
    const result = await pushApproval({
      deviceToken: account.apns_token,
      env: account.apns_env,
      requestId,
      displayName: name,
      expiresInSeconds: REQUEST_MINUTES * 60,
    });
    pushed = result === "sent";
    if (result === "bad-token") await query("UPDATE account SET apns_token = NULL WHERE user_hash = $1", [userHash]);
  }
  return { kind: "wait", requestId, browserSecret, displayName: name, pushed };
}

// MARK: - The phone decides

export interface PendingRequest {
  id: string;
  client: Client;
  name: string;
  createdAt: string;
}

export async function pendingRequests(userHash: string): Promise<PendingRequest[]> {
  return query<PendingRequest>(
    `SELECT id, client, display_name AS name, created_at AS "createdAt" FROM auth_request
     WHERE user_hash = $1 AND status = 'pending' AND expires_at > now() ORDER BY created_at DESC`,
    [userHash],
  );
}

/** Allow or deny. Allow hands the data key to the request, sealed under the server key until the token exchange. */
export async function decide(account: Account, requestId: string, allow: boolean): Promise<boolean> {
  const rows = await query<{ id: string }>(
    `UPDATE auth_request SET status = $3, pending_dk = $4
     WHERE id = $1 AND user_hash = $2 AND status = 'pending' AND expires_at > now() RETURNING id`,
    [requestId, account.userHash, allow ? "allowed" : "denied", allow ? sealForServer(account.dataKey, `pending:${requestId}`) : null],
  );
  return rows.length > 0;
}

/** The authorize page asks with its secret. Once allowed, it gets the redirect carrying a fresh one-time code. */
export async function poll(publicId: string, requestId: string, browserSecret: string): Promise<{ status: "pending" | "expired" } | { status: "done"; location: string }> {
  const rows = await query<{ status: string; redirect_uri: string; state: string | null; expired: boolean }>(
    `SELECT status, redirect_uri, state, expires_at < now() AS expired FROM auth_request a
     JOIN account u ON u.user_hash = a.user_hash
     WHERE a.id = $1 AND a.browser_hash = $2 AND u.public_id = $3`,
    [requestId, sha256(browserSecret), publicId],
  );
  const row = rows[0];
  if (!row || row.expired) return { status: "expired" };
  if (row.status === "pending") return { status: "pending" };
  if (row.status === "denied") {
    const out = errorRedirect(row.redirect_uri, publicId, "access_denied", row.state, "Not allowed on the phone");
    await query("DELETE FROM auth_request WHERE id = $1", [requestId]);
    return { status: "done", location: (out as { location: string }).location };
  }
  if (row.status !== "allowed") return { status: "expired" };
  const code = secret();
  const issued = await query<{ id: string }>(
    `UPDATE auth_request SET status = 'issued', code_hash = $2, expires_at = now() + make_interval(mins => $3)
     WHERE id = $1 AND status = 'allowed' RETURNING id`,
    [requestId, sha256(code), CODE_MINUTES],
  );
  if (!issued.length) return { status: "expired" };
  const url = new URL(row.redirect_uri);
  url.searchParams.set("code", code);
  if (row.state) url.searchParams.set("state", row.state);
  url.searchParams.set("iss", issuer(publicId));
  return { status: "done", location: url.toString() };
}

// MARK: - Tokens

export interface TokenResponse {
  access_token: string;
  token_type: "Bearer";
  expires_in: number;
  refresh_token: string;
  scope: string;
}

async function mint(grantId: string, dataKey: Buffer): Promise<TokenResponse> {
  const access = secret();
  const refresh = secret();
  await query(
    `INSERT INTO oauth_token (token_hash, grant_id, kind, dk_wrap, expires_at) VALUES
     ($1, $3, 'access', $4, now() + make_interval(secs => $6)),
     ($2, $3, 'refresh', $5, now() + make_interval(days => $7))`,
    [sha256(access), sha256(refresh), grantId, wrap(dataKey, access, "access"), wrap(dataKey, refresh, "refresh"), ACCESS_SECONDS, REFRESH_DAYS],
  );
  return { access_token: access, token_type: "Bearer", expires_in: ACCESS_SECONDS, refresh_token: refresh, scope: SCOPE };
}

export async function token(publicId: string, userHash: string, form: URLSearchParams): Promise<TokenResponse> {
  const resource = form.get("resource");
  if (resource && !sameResource(resource, publicId)) throw new OAuthError("invalid_target", "Wrong resource");
  switch (form.get("grant_type")) {
    case "authorization_code":
      return exchangeCode(userHash, form);
    case "refresh_token":
      return refresh(userHash, form);
    default:
      throw new OAuthError("unsupported_grant_type", "Use authorization_code or refresh_token");
  }
}

async function exchangeCode(userHash: string, form: URLSearchParams): Promise<TokenResponse> {
  const code = form.get("code") ?? "";
  const rows = await query<{
    id: string;
    user_hash: string;
    client_id: string;
    client: Client;
    display_name: string;
    redirect_uri: string;
    code_challenge: string;
    status: string;
    pending_dk: string | null;
    grant_id: string | null;
    expired: boolean;
  }>(
    `SELECT id, user_hash, client_id, client, display_name, redirect_uri, code_challenge, status, pending_dk, grant_id,
            expires_at < now() AS expired
     FROM auth_request WHERE code_hash = $1`,
    [sha256(code)],
  );
  const req = rows[0];
  const invalid = new OAuthError("invalid_grant", "The code is invalid, expired or already used");
  if (!req || req.user_hash !== userHash) throw invalid;
  if (req.status === "exchanged") {
    // A code used twice: someone else may hold it. Revoke what the first use got (OAuth 2.1 §4.1.3).
    if (req.grant_id) await query("DELETE FROM oauth_grant WHERE id = $1", [req.grant_id]);
    throw invalid;
  }
  if (req.status !== "issued" || req.expired || !req.pending_dk) throw invalid;
  if (form.get("client_id") !== req.client_id) throw new OAuthError("invalid_client", "Wrong client", 401);
  if (form.get("redirect_uri") !== req.redirect_uri) throw invalid;
  if (!pkceMatches(form.get("code_verifier") ?? "", req.code_challenge)) throw invalid;

  const claimed = await query<{ id: string }>(
    "UPDATE auth_request SET status = 'exchanged', pending_dk = NULL WHERE id = $1 AND status = 'issued' RETURNING id",
    [req.id],
  );
  if (!claimed.length) throw invalid;
  const dataKey = openForServer(req.pending_dk, `pending:${req.id}`);
  const grantId = newId("g_");
  await query(
    "INSERT INTO oauth_grant (id, user_hash, client_id, client, name, last_used_at) VALUES ($1, $2, $3, $4, $5, now())",
    [grantId, userHash, req.client_id, req.client, req.display_name],
  );
  await query("UPDATE auth_request SET grant_id = $2 WHERE id = $1", [req.id, grantId]);
  return mint(grantId, dataKey);
}

async function refresh(userHash: string, form: URLSearchParams): Promise<TokenResponse> {
  const presented = form.get("refresh_token") ?? "";
  const rows = await query<{ grant_id: string; dk_wrap: string; used: boolean; expired: boolean; user_hash: string; client_id: string }>(
    `SELECT t.grant_id, t.dk_wrap, t.used_at IS NOT NULL AS used, t.expires_at < now() AS expired, g.user_hash, g.client_id
     FROM oauth_token t JOIN oauth_grant g ON g.id = t.grant_id WHERE t.token_hash = $1 AND t.kind = 'refresh'`,
    [sha256(presented)],
  );
  const row = rows[0];
  const invalid = new OAuthError("invalid_grant", "The refresh token is invalid, expired or already used");
  if (!row || row.user_hash !== userHash) throw invalid;
  if (form.get("client_id") !== row.client_id) throw new OAuthError("invalid_client", "Wrong client", 401);
  if (row.used) {
    // A rotated-out refresh token came back: it was copied. End the whole grant.
    await query("DELETE FROM oauth_grant WHERE id = $1", [row.grant_id]);
    throw invalid;
  }
  if (row.expired) throw invalid;
  const marked = await query<{ token_hash: string }>(
    "UPDATE oauth_token SET used_at = now() WHERE token_hash = $1 AND used_at IS NULL RETURNING token_hash",
    [sha256(presented)],
  );
  if (!marked.length) throw invalid;
  const dataKey = unwrap(row.dk_wrap, presented, "refresh");
  await query("DELETE FROM oauth_token WHERE grant_id = $1 AND expires_at < now()", [row.grant_id]);
  return mint(row.grant_id, dataKey);
}

/** The user and data key behind a bearer token on this phone's MCP URL, or null. */
export async function openAccessToken(userHash: string, bearer: string): Promise<{ dataKey: Buffer } | null> {
  const rows = await query<{ grant_id: string; dk_wrap: string; user_hash: string }>(
    `SELECT t.grant_id, t.dk_wrap, g.user_hash FROM oauth_token t JOIN oauth_grant g ON g.id = t.grant_id
     WHERE t.token_hash = $1 AND t.kind = 'access' AND t.expires_at > now()`,
    [sha256(bearer)],
  );
  const row = rows[0];
  // Audience: a token from one phone's issuer never opens another phone's URL.
  if (!row || row.user_hash !== userHash) return null;
  await query("UPDATE oauth_grant SET last_used_at = now() WHERE id = $1 AND last_used_at < now() - interval '1 minute'", [row.grant_id]);
  return { dataKey: unwrap(row.dk_wrap, bearer, "access") };
}
