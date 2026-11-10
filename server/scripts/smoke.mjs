// End-to-end against a running server: sync, pair, OAuth, MCP tool calls, revoke, delete.
// Usage: node scripts/smoke.mjs [baseUrl]   (default http://localhost:8788)
import { createHash, randomBytes } from "node:crypto";

const BASE = (process.argv[2] ?? "http://localhost:8788").replace(/\/$/, "");
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
const b64url = (buf) => buf.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

const deviceKey = "tt_" + b64url(randomBytes(32));
const device = { authorization: `Bearer ${deviceKey}` };

// 1. The phone pushes its data.
let r = await fetch(`${BASE}/v1/snapshot`, { method: "PUT", headers: { ...device, "content-type": "application/json" }, body: JSON.stringify(fixture) });
check(r.status === 200, `snapshot stored (${r.status})`);
r = await fetch(`${BASE}/v1/snapshot`, { method: "PUT", headers: { ...device, "content-type": "application/json" }, body: JSON.stringify({ ...fixture, generatedAt: "2000-01-01T00:00:00Z" }) });
check(r.status === 409, "older snapshot refused");
r = await fetch(`${BASE}/v1/snapshot`, { method: "PUT", headers: { "content-type": "application/json" }, body: "{}" });
check(r.status === 401, "no device key → 401");

// 2. Discovery, like an MCP client does it.
r = await fetch(`${BASE}/mcp`, { method: "POST", headers: { "content-type": "application/json" }, body: "{}" });
check(r.status === 401 && /resource_metadata/.test(r.headers.get("www-authenticate") ?? ""), "unauthenticated /mcp advertises resource metadata");
const prm = await (await fetch(`${BASE}/.well-known/oauth-protected-resource/mcp`)).json().catch(() => null);
const prmRoot = prm ?? (await (await fetch(`${BASE}/.well-known/oauth-protected-resource`)).json());
check(prmRoot.authorization_servers?.[0] === BASE, "protected resource metadata points at this server");
const as = await (await fetch(`${BASE}/.well-known/oauth-authorization-server`)).json();
check(as.registration_endpoint && as.token_endpoint && as.authorization_endpoint, "authorization server metadata complete");

// 3. Dynamic client registration.
const redirectUri = "http://localhost:9/callback";
r = await fetch(as.registration_endpoint, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ client_name: "Smoke Client", redirect_uris: [redirectUri], token_endpoint_auth_method: "none", grant_types: ["authorization_code", "refresh_token"], response_types: ["code"] }),
});
const client = await r.json();
check(r.status === 201 && client.client_id, "client registered");

// 4. Authorize: the browser lands on the pairing page and gets a code.
const verifier = b64url(randomBytes(32));
const challenge = b64url(createHash("sha256").update(verifier).digest());
const authUrl = new URL(as.authorization_endpoint);
authUrl.search = new URLSearchParams({ response_type: "code", client_id: client.client_id, redirect_uri: redirectUri, scope: "meetings:read", state: "s123", code_challenge: challenge, code_challenge_method: "S256", resource: `${BASE}/mcp` }).toString();
r = await fetch(authUrl, { headers: { accept: "application/json" } });
const pairing = await r.json();
check(r.status === 200 && /^\d{6}$/.test(pairing.code ?? ""), `pairing code issued for "${pairing.clientName}"`);
const html = await (await fetch(authUrl)).text();
check(html.includes("Open TouchTips") && html.includes("Smoke Client"), "pairing page renders");
let status = await (await fetch(`${BASE}/pair/${pairing.code}/status`)).json();
check(status.status === "pending", "status pending before approval");

// 5. The phone approves.
r = await fetch(`${BASE}/v1/pair/${pairing.code}`, { headers: device });
check(r.status === 200 && (await r.json()).clientName === "Smoke Client", "app sees what it is approving");
r = await fetch(`${BASE}/v1/pair/${pairing.code}/approve`, { method: "POST", headers: device });
check(r.status === 200, "approve accepted");
r = await fetch(`${BASE}/v1/pair/${pairing.code}/approve`, { method: "POST", headers: device });
check(r.status === 404, "code is single-use");
status = await (await fetch(`${BASE}/pair/${pairing.code}/status`)).json();
check(status.redirectTo?.startsWith(redirectUri), "browser gets the redirect");
const authCode = new URL(status.redirectTo).searchParams.get("code");
check(authCode && new URL(status.redirectTo).searchParams.get("state") === "s123", "redirect carries code and state");

// 6. Token exchange.
r = await fetch(as.token_endpoint, {
  method: "POST",
  headers: { "content-type": "application/x-www-form-urlencoded" },
  body: new URLSearchParams({ grant_type: "authorization_code", code: authCode, redirect_uri: redirectUri, client_id: client.client_id, code_verifier: verifier, resource: `${BASE}/mcp` }),
});
const tokens = await r.json();
check(r.status === 200 && tokens.access_token, `access token issued (scope "${tokens.scope}")`);

// 7. MCP calls.
let nextId = 1;
const mcpHeaders = { authorization: `Bearer ${tokens.access_token}`, "content-type": "application/json", accept: "application/json, text/event-stream", "mcp-protocol-version": "2025-06-18" };
async function rpc(method, params, extra = {}) {
  const res = await fetch(`${BASE}/mcp`, { method: "POST", headers: { ...mcpHeaders, ...extra }, body: JSON.stringify({ jsonrpc: "2.0", id: nextId++, method, params }) });
  const text = await res.text();
  if (res.headers.get("content-type")?.includes("text/event-stream")) {
    const data = text.split("\n").filter((l) => l.startsWith("data:")).map((l) => l.slice(5).trim());
    return { status: res.status, body: JSON.parse(data[data.length - 1]) };
  }
  return { status: res.status, body: text ? JSON.parse(text) : null };
}
let res = await rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "smoke", version: "0" } });
check(res.status === 200 && res.body.result?.serverInfo?.name === "TouchTips", "initialize");
check(/Quote the "when" field/.test(res.body.result?.instructions ?? ""), "server instructions delivered");
res = await rpc("tools/list", {});
const toolNames = (res.body.result?.tools ?? []).map((t) => t.name).sort();
check(JSON.stringify(toolNames) === JSON.stringify(["get_person", "list_meetings", "search_people"]), `tools: ${toolNames.join(", ")}`);
res = await rpc("tools/call", { name: "search_people", arguments: { query: "jose" } });
const found = res.body.result?.structuredContent?.people ?? [];
check(found.length === 1 && found[0].name === "José Álvarez" && found[0].meetings[0].when === "2022" && found[0].meetings[0].confidence === "estimated", `search_people → ${found[0]?.name} met ${found[0]?.meetings[0]?.when}`);
res = await rpc("tools/call", { name: "get_person", arguments: { id: "p-sam" } });
const sam = res.body.result?.structuredContent?.person;
check(sam?.meetings[0]?.when === "March 14, 2024 at 3:12 PM" && sam.meetings[0].place?.name === "Brooklyn Boulders", `get_person → ${sam?.meetings[0]?.when} at ${sam?.meetings[0]?.place?.name}`);
res = await rpc("tools/call", { name: "list_meetings", arguments: { place: "boulders" } });
check(res.body.result?.structuredContent?.meetings?.length === 1, "list_meetings filters by place");

// 8. Revoke from the phone, then the token must stop working.
r = await fetch(`${BASE}/v1/clients`, { headers: device });
const { clients } = await r.json();
check(clients.length === 1 && clients[0].name === "Smoke Client", "phone lists the paired client");
r = await fetch(`${BASE}/v1/clients/${encodeURIComponent(clients[0].id)}`, { method: "DELETE", headers: device });
check(r.status === 200, "client revoked");
res = await rpc("tools/call", { name: "search_people", arguments: { query: "sam" } });
check(res.status === 401, "revoked token rejected");

// 9. Delete everything.
r = await fetch(`${BASE}/v1/account`, { method: "DELETE", headers: device });
check(r.status === 204, "account deleted");
r = await fetch(`${BASE}/v1/clients`, { headers: device });
check((await r.json()).clients.length === 0, "no clients remain");

// 10. Universal link plumbing.
const aasa = await (await fetch(`${BASE}/.well-known/apple-app-site-association`)).json();
check(aasa.applinks.details[0].appIDs[0] === "G2U3K77U5W.sh.harivan.touchtips", "apple-app-site-association served");

console.log("\nsmoke passed");
