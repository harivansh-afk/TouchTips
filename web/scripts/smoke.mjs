// End-to-end against a running deployment, playing both the phone and an MCP client (as Claude would):
// sync, discovery, registration, authorize, Allow on the phone, PKCE exchange, MCP calls, refresh rotation,
// replay detection, deny, disconnect, isolation between phones, connector URLs, delete.
// Usage: node scripts/smoke.mjs [baseUrl]   (default http://localhost:5173)
import { createHash, randomBytes } from "node:crypto";

const BASE = (process.argv[2] ?? "http://localhost:5173").replace(/\/$/, "");
const REDIRECT = "https://claude.ai/api/mcp/auth_callback";
const fixture = {
  version: 1,
  generatedAt: new Date().toISOString(),
  timeZone: "America/New_York",
  people: [
    { id: "p-sam", name: "Sam Okafor", note: "climbing gym", createdAt: "2024-03-14T19:12:00Z" },
    { id: "p-jose", name: "José Álvarez", note: null, createdAt: "2023-01-01T00:00:00Z" },
  ],
  places: [{ id: 1, name: "Brooklyn Boulders", latitude: 40.68, longitude: -73.98 }],
  meets: [
    { personId: "p-sam", start: "2024-03-14T19:12:00Z", end: "2024-03-14T19:12:00Z", precision: "exact", tier: 0, placeId: 1, userSet: true, dateConfirmed: true, placeConfirmed: true },
    { personId: "p-jose", start: "2022-11-01T00:00:00Z", end: "2023-02-01T00:00:00Z", precision: "year", tier: 3, placeId: null, userSet: false, dateConfirmed: false, placeConfirmed: false },
  ],
};

let step = 0;
function check(cond, what) {
  step++;
  if (!cond) {
    console.error(`FAIL ${step}: ${what}`);
    process.exit(1);
  }
  console.log(`ok ${step}: ${what}`);
}

// A fresh deployment can report success a few seconds before the alias serves it.
for (let i = 0; i < 30; i++) {
  const probe = await fetch(`${BASE}/v1/keys`).catch(() => null);
  if (probe?.status === 401) break;
  await new Promise((r) => setTimeout(r, 3000));
}

function newPhone() {
  const key = "tt_" + randomBytes(32).toString("base64url");
  return { authorization: `Bearer ${key}`, "content-type": "application/json" };
}
const phone = newPhone();
const api = (path, init = {}, headers = phone) => fetch(`${BASE}${path}`, { ...init, headers: { ...headers, ...init.headers } });

let nextId = 1;
async function rpc(url, method, params, token) {
  const headers = { "content-type": "application/json", accept: "application/json, text/event-stream", "mcp-protocol-version": "2025-06-18" };
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await fetch(url, { method: "POST", headers, body: JSON.stringify({ jsonrpc: "2.0", id: nextId++, method, params }) });
  const text = await res.text();
  if (res.headers.get("content-type")?.includes("text/event-stream")) {
    const data = text.split("\n").filter((l) => l.startsWith("data:")).map((l) => l.slice(5).trim());
    return { status: res.status, headers: res.headers, body: JSON.parse(data[data.length - 1]) };
  }
  let body = null;
  try { body = text ? JSON.parse(text) : null; } catch { body = { raw: text }; }
  return { status: res.status, headers: res.headers, body };
}

// 1. The phone pushes its data.
let r = await api("/v1/snapshot", { method: "PUT", body: JSON.stringify(fixture) });
check(r.status === 200, `snapshot stored (${r.status})`);
r = await api("/v1/snapshot", { method: "PUT", body: JSON.stringify({ ...fixture, generatedAt: "2000-01-01T00:00:00Z" }) });
check(r.status === 409, "older snapshot refused");
r = await fetch(`${BASE}/v1/snapshot`, { method: "PUT", headers: { "content-type": "application/json" }, body: "{}" });
check(r.status === 401, "no device key → 401");

// 2. The user taps Claude in the app: the phone's MCP URL, and a window for the approval prompt.
r = await api("/v1/connect", { method: "POST", body: JSON.stringify({ client: "claude" }) });
const { url: mcpUrl } = await r.json();
check(r.status === 200 && /\/u\/[A-Za-z0-9_-]{22}\/mcp$/.test(mcpUrl), `phone's MCP URL ${mcpUrl}`);
r = await api("/v1/keys", { method: "POST", body: JSON.stringify({ client: "claude" }) });
check(r.status === 400, "OAuth clients get no connector URL");

// 3. Discovery, the way an MCP client does it.
let res = await rpc(mcpUrl, "initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "smoke", version: "0" } });
const challenge = res.headers.get("www-authenticate") ?? "";
check(res.status === 401 && /resource_metadata="([^"]+)"/.test(challenge), "no token → 401 with resource_metadata");
const prm = await (await fetch(/resource_metadata="([^"]+)"/.exec(challenge)[1])).json();
check(prm.resource === mcpUrl && prm.authorization_servers?.length === 1, "protected resource metadata names one issuer");
const issuerUrl = new URL(prm.authorization_servers[0]);
const asMeta = await (await fetch(`${issuerUrl.origin}/.well-known/oauth-authorization-server${issuerUrl.pathname}`)).json();
check(asMeta.issuer === prm.authorization_servers[0] && asMeta.code_challenge_methods_supported.join() === "S256", "authorization server metadata (RFC 8414 path)");
for (const path of [`/.well-known/openid-configuration${issuerUrl.pathname}`, `${issuerUrl.pathname}/.well-known/openid-configuration`]) {
  const alt = await (await fetch(`${issuerUrl.origin}${path}`)).json();
  check(alt.issuer === asMeta.issuer, `metadata also at ${path.replace(issuerUrl.pathname, "/u/…")}`);
}
r = await fetch(asMeta.token_endpoint, { method: "OPTIONS", headers: { origin: "https://example.com", "access-control-request-method": "POST" } });
check(r.status === 204 && r.headers.get("access-control-allow-origin") === "*", "CORS preflight on the token endpoint");

// 4. Dynamic client registration.
r = await fetch(asMeta.registration_endpoint, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ client_name: "Claude", redirect_uris: ["http://evil.example/cb"] }) });
check(r.status === 400, "plain-http redirect refused at registration");
r = await fetch(asMeta.registration_endpoint, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ client_name: "Claude", redirect_uris: [REDIRECT], token_endpoint_auth_method: "none" }),
});
const client = await r.json();
check(r.status === 201 && client.client_id && client.token_endpoint_auth_method === "none", "client registered");

// One authorization, start to finish. Returns the page's request id and secret, and the PKCE verifier.
async function startAuthorize({ redirect = REDIRECT, clientId = client.client_id, endpoint = asMeta.authorization_endpoint, extra = {} } = {}) {
  const verifier = randomBytes(32).toString("base64url");
  const u = new URL(endpoint);
  const params = {
    response_type: "code",
    client_id: clientId,
    redirect_uri: redirect,
    code_challenge: createHash("sha256").update(verifier).digest("base64url"),
    code_challenge_method: "S256",
    state: "xyz",
    scope: "read",
    resource: mcpUrl,
    ...extra,
  };
  for (const [k, v] of Object.entries(params)) if (v !== null) u.searchParams.set(k, v);
  const page = await fetch(u, { redirect: "manual" });
  const html = page.status === 200 ? await page.text() : "";
  const ask = /const ask = \{ request: "([^"]+)", secret: "([^"]+)" \}/.exec(html);
  const number = Number(/id="number">(\d+)</.exec(html)?.[1]);
  return { page, html, verifier, number, request: ask?.[1], secret: ask?.[2], pollUrl: `${new URL(endpoint).origin}${new URL(endpoint).pathname.replace(/authorize$/, "poll")}` };
}
const pollOnce = async (a, secret = a.secret) =>
  (await fetch(a.pollUrl, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ request: a.request, secret }) })).json();
async function exchange(a, location, overrides = {}) {
  const code = new URL(location).searchParams.get("code");
  const body = new URLSearchParams({ grant_type: "authorization_code", code, redirect_uri: REDIRECT, client_id: client.client_id, code_verifier: a.verifier, resource: mcpUrl, ...overrides });
  const res = await fetch(asMeta.token_endpoint, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body });
  return { status: res.status, body: await res.json() };
}
// The phone taps the number the page shows.
const allow = (a, headers = phone, number = a.number) =>
  api(`/v1/requests/${a.request}`, { method: "POST", body: JSON.stringify({ allow: true, number }) }, headers);

// 5. Authorize: bad requests first.
let a = await startAuthorize({ redirect: "https://evil.example/cb" });
check(a.page.status === 200 && /Can(&#39;|.)t connect/.test(a.html), "unregistered redirect gets an error page, never a redirect");
a = await startAuthorize({ extra: { code_challenge_method: "plain" } });
check(a.page.status === 200 && !a.request && /PKCE/.test(a.html), "PKCE plain refused on the page, no redirect");
a = await startAuthorize({ extra: { resource: "https://evil.example/mcp" } });
check(a.page.status === 200 && !a.request, "wrong resource refused on the page, no redirect");
a = await startAuthorize({ extra: { response_type: "token" } });
check(a.page.status === 200 && !a.request, "response_type=token can't be used as an open redirect");

// 6. The real one: the page waits, the phone sees the request named for the client the user tapped.
a = await startAuthorize();
check(a.page.status === 200 && a.request && a.secret && a.number >= 10 && a.number <= 99, `authorize page waits for the phone, showing ${a.number}`);
check(a.page.headers.get("x-frame-options") === "DENY" && /frame-ancestors 'none'/.test(a.page.headers.get("content-security-policy") ?? ""), "authorize page can't be framed");
check((await pollOnce(a)).status === "pending", "page polls: pending");
let { requests } = await (await api("/v1/requests")).json();
check(requests.length === 1 && requests[0].id === a.request && requests[0].name === "Claude" && requests[0].recognised, `phone sees "Allow ${requests[0]?.name}?"`);
check(requests[0].choices.length === 3 && requests[0].choices.includes(a.number), `phone offers ${requests[0].choices.join(", ")}`);
const stranger = newPhone();
await api("/v1/snapshot", { method: "PUT", body: JSON.stringify(fixture) }, stranger);
r = await allow(a, stranger);
check(r.status === 404, "another phone can't allow it");
r = await api(`/v1/requests/${a.request}`, { method: "POST", body: JSON.stringify({ allow: true }) });
check(r.status === 400, "Allow without the page's number is refused");
r = await allow(a);
check(r.status === 200 && (await r.json()).outcome === "allowed", "phone taps the matching number");
check((await pollOnce(a, randomBytes(32).toString("base64url"))).status === "expired", "polling without the page's secret gets nothing");
let done = await pollOnce(a);
const location = new URL(done.location);
check(done.status === "done" && location.origin + location.pathname === REDIRECT && location.searchParams.get("state") === "xyz" && location.searchParams.get("iss") === asMeta.issuer, "page redirects with code, state and iss");
check((await pollOnce(a)).status === "expired", "the code is handed out once");

// 7. Token exchange.
let t = await exchange(a, done.location, { code_verifier: randomBytes(32).toString("base64url") });
check(t.status === 400 && t.body.error === "invalid_grant", "wrong PKCE verifier refused");
t = await exchange(a, done.location, { client_id: "c_someoneelse" });
check(t.status === 401 && t.body.error === "invalid_client", "wrong client refused");
t = await exchange(a, done.location);
check(t.status === 200 && t.body.token_type === "Bearer" && t.body.access_token && t.body.refresh_token && t.body.expires_in === 3600, "tokens issued");
let tokens = t.body;

// 8. MCP with the token.
res = await rpc(mcpUrl, "initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "smoke", version: "0" } }, tokens.access_token);
check(res.status === 200 && res.body.result?.serverInfo?.name === "TouchTips", `initialize (${res.status})`);
check(/Quote the "when" field/.test(res.body.result?.instructions ?? ""), "server instructions delivered");
res = await rpc(mcpUrl, "tools/list", {}, tokens.access_token);
const toolNames = (res.body.result?.tools ?? []).map((x) => x.name).sort();
check(JSON.stringify(toolNames) === JSON.stringify(["get_person", "list_meetings", "search_people"]), `tools: ${toolNames.join(", ")}`);
res = await rpc(mcpUrl, "tools/call", { name: "search_people", arguments: { query: "jose" } }, tokens.access_token);
const found = res.body.result?.structuredContent?.people ?? [];
check(found.length === 1 && found[0].name === "José Álvarez" && found[0].meetings[0].when === "2022", `search_people → ${found[0]?.name} met ${found[0]?.meetings[0]?.when}`);
res = await rpc(mcpUrl, "tools/call", { name: "get_person", arguments: { id: "p-sam" } }, tokens.access_token);
const sam = res.body.result?.structuredContent?.person;
check(sam?.meetings[0]?.when === "March 14, 2024 at 3:12 PM" && sam.meetings[0].place?.name === "Brooklyn Boulders", `get_person → ${sam?.meetings[0]?.when} at ${sam?.meetings[0]?.place?.name}`);
res = await rpc(mcpUrl, "tools/list", {}, randomBytes(32).toString("base64url"));
check(res.status === 401 && /error="invalid_token"/.test(res.headers.get("www-authenticate") ?? ""), "made-up token → 401 invalid_token");

// 9. Isolation: this token opens nothing on another phone's URL.
r = await api("/v1/connect", { method: "POST", body: JSON.stringify({ client: "claude" }) }, stranger);
const strangerUrl = (await r.json()).url;
res = await rpc(strangerUrl, "tools/list", {}, tokens.access_token);
check(res.status === 401, "token from one phone is refused on another's URL");

// 10. Refresh rotation and replay detection.
const refreshWith = async (rt) => {
  const res = await fetch(asMeta.token_endpoint, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: rt, client_id: client.client_id }) });
  return { status: res.status, body: await res.json() };
};
t = await refreshWith(tokens.refresh_token);
check(t.status === 200 && t.body.refresh_token !== tokens.refresh_token, "refresh rotates both tokens");
const rotated = t.body;
res = await rpc(mcpUrl, "tools/list", {}, rotated.access_token);
check(res.status === 200, "new access token works");
t = await refreshWith(tokens.refresh_token);
check(t.status === 400 && t.body.error === "invalid_grant", "replayed refresh token refused");
res = await rpc(mcpUrl, "tools/list", {}, rotated.access_token);
check(res.status === 200, "…a quick retry (a lost response) doesn't end the grant");

// 11. Deny, and the wrong number.
a = await startAuthorize();
await api(`/v1/requests/${a.request}`, { method: "POST", body: JSON.stringify({ allow: false }) });
done = await pollOnce(a);
check(done.status === "done" && new URL(done.location).searchParams.get("error") === "access_denied", "Don't Allow → access_denied back to the client");
a = await startAuthorize();
({ requests } = await (await api("/v1/requests")).json());
const wrong = requests.find((q) => q.id === a.request).choices.find((n) => n !== a.number);
r = await allow(a, phone, wrong);
check((await r.json()).outcome === "wrong-number", "a different number than the page's is refused…");
check((await allow(a)).status === 404, "…with no second guess");
done = await pollOnce(a);
check(new URL(done.location).searchParams.get("error") === "access_denied", "…and the client is told no");

// 12. A code used twice revokes what the first use got.
a = await startAuthorize();
await allow(a);
done = await pollOnce(a);
t = await exchange(a, done.location);
tokens = t.body;
t = await exchange(a, done.location);
check(t.status === 400 && t.body.error === "invalid_grant", "code reuse refused");
res = await rpc(mcpUrl, "tools/list", {}, tokens.access_token);
check(res.status === 401, "…and the first exchange's tokens are revoked");

// 13. Disconnect from the phone.
a = await startAuthorize();
await allow(a);
done = await pollOnce(a);
tokens = (await exchange(a, done.location)).body;
let { keys } = await (await api("/v1/keys")).json();
const grant = keys.find((k) => k.client === "claude" && k.lastUsedAt);
check(grant?.name === "Claude", "phone lists Claude as connected");
r = await api(`/v1/keys/${grant.id}`, { method: "DELETE" });
check(r.status === 200, "phone disconnects Claude");
res = await rpc(mcpUrl, "tools/list", {}, tokens.access_token);
check(res.status === 401, "disconnected token refused at once");

// 14. The phone names the client only when the sign-in returns to that client's own site.
//     Here the user tapped ChatGPT, but a client registered as "Claude" returning to claude.ai asks instead.
await api("/v1/connect", { method: "POST", body: JSON.stringify({ client: "chatgpt" }) }, stranger);
a = await startAuthorize({ endpoint: `${new URL(strangerUrl).origin}${new URL(strangerUrl).pathname.replace(/mcp$/, "oauth/authorize")}`, extra: { resource: strangerUrl } });
({ requests } = await (await api("/v1/requests", {}, stranger)).json());
check(requests.length === 1 && requests[0].name === "Claude · claude.ai" && !requests[0].recognised, `mismatched client shows its host: "${requests[0]?.name}"`);
a = await startAuthorize({ redirect: "http://localhost:4000/cb", clientId: (await (await fetch(asMeta.registration_endpoint, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ client_name: "Claude", redirect_uris: ["http://localhost:4000/cb"] }) })).json()).client_id, endpoint: `${new URL(strangerUrl).origin}${new URL(strangerUrl).pathname.replace(/mcp$/, "oauth/authorize")}`, extra: { resource: strangerUrl } });
({ requests } = await (await api("/v1/requests", {}, stranger)).json());
check(requests.some((q) => q.name === "Claude · a computer" && !q.recognised), "a localhost sign-in never passes as a named client");

// 14b. Outside a connect window, nothing reaches the phone unless the user opens it from the sign-in page.
const quiet = newPhone();
r = await api("/v1/connect", { method: "POST", body: JSON.stringify({ client: "claude" }) }, quiet);
const quietUrl = (await r.json()).url;
// The app closes the window after Allow; here it stands in for ten minutes passing.
r = await api("/v1/connect", { method: "DELETE" }, quiet);
check(r.status === 200, "window closed");
a = await startAuthorize({ endpoint: quietUrl.replace(/mcp$/, "oauth/authorize"), extra: { resource: quietUrl } });
({ requests } = await (await api("/v1/requests", {}, quiet)).json());
check(a.request && requests.length === 0, "a sign-in outside the window never reaches the screen");
({ requests } = await (await api(`/v1/requests?opened=${a.request}`, {}, quiet)).json());
check(requests.length === 1 && requests[0].id === a.request, "…unless the user opens it from its own page");
await api("/v1/account", { method: "DELETE" }, quiet);

// 15. Connector URLs, for clients that can't do OAuth.
r = await api("/v1/keys", { method: "POST", body: JSON.stringify({ client: "instinct" }) });
const minted = await r.json();
check(r.status === 201 && minted.url?.startsWith(`${BASE}/c/`), "connector URL minted for Instinct");
res = await rpc(minted.url, "tools/call", { name: "search_people", arguments: { query: "sam" } });
check(res.status === 200 && res.body.result?.structuredContent?.people?.[0]?.name === "Sam Okafor", "connector URL opens the sealed data");
res = await rpc(`${BASE}/c/${"x".repeat(43)}/mcp`, "tools/list", {});
check(res.status === 404, "unknown connector → 404");

// 16. Delete everything.
r = await api("/v1/account", { method: "DELETE" });
check(r.status === 204, "account deleted");
res = await rpc(minted.url, "tools/list", {});
check(res.status === 404, "connector gone");
res = await rpc(mcpUrl, "tools/list", {}, rotated.access_token);
check(res.status === 404, "the phone's MCP URL is gone");
await api("/v1/account", { method: "DELETE" }, stranger);

// 17. Universal links.
const aasa = await (await fetch(`${BASE}/.well-known/apple-app-site-association`)).json();
check(aasa.applinks.details[0].components.some((c) => c["/"] === "/connect/*"), "apple-app-site-association covers /connect/*");

console.log("\nsmoke passed");
