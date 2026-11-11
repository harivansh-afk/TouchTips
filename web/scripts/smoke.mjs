// End-to-end against a running deployment: sync, mint a connector URL, call tools through it, revoke, delete.
// Usage: node scripts/smoke.mjs [baseUrl]   (default http://localhost:5173)
import { randomBytes } from "node:crypto";

const BASE = (process.argv[2] ?? "http://localhost:5173").replace(/\/$/, "");
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

const deviceKey = "tt_" + randomBytes(32).toString("base64url");
const device = { authorization: `Bearer ${deviceKey}`, "content-type": "application/json" };

// 1. The phone pushes its data.
let r = await fetch(`${BASE}/v1/snapshot`, { method: "PUT", headers: device, body: JSON.stringify(fixture) });
check(r.status === 200, `snapshot stored (${r.status})`);
r = await fetch(`${BASE}/v1/snapshot`, { method: "PUT", headers: device, body: JSON.stringify({ ...fixture, generatedAt: "2000-01-01T00:00:00Z" }) });
check(r.status === 409, "older snapshot refused");
r = await fetch(`${BASE}/v1/snapshot`, { method: "PUT", headers: { "content-type": "application/json" }, body: "{}" });
check(r.status === 401, "no device key → 401");

// 2. Connect Claude: one URL.
r = await fetch(`${BASE}/v1/keys`, { method: "POST", headers: device, body: JSON.stringify({ client: "claude" }) });
const minted = await r.json();
check(r.status === 201 && minted.url?.startsWith(`${BASE}/c/`) && minted.url.endsWith("/mcp"), `connector minted for ${minted.name}`);
r = await fetch(`${BASE}/v1/keys`, { method: "POST", headers: device, body: JSON.stringify({ client: "other", name: "Grok bot" }) });
const second = await r.json();
check(r.status === 201 && second.name === "Grok bot", "second connector with a custom name");
r = await fetch(`${BASE}/v1/keys`, { headers: device });
let { keys } = await r.json();
check(keys.length === 2 && !keys.some((k) => k.url), "phone lists both, URLs never echoed back");

// 3. MCP through the URL, no auth headers at all.
let nextId = 1;
async function rpc(url, method, params) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json", accept: "application/json, text/event-stream", "mcp-protocol-version": "2025-06-18" },
    body: JSON.stringify({ jsonrpc: "2.0", id: nextId++, method, params }),
  });
  const text = await res.text();
  if (res.headers.get("content-type")?.includes("text/event-stream")) {
    const data = text.split("\n").filter((l) => l.startsWith("data:")).map((l) => l.slice(5).trim());
    return { status: res.status, body: JSON.parse(data[data.length - 1]) };
  }
  let body = null;
  try { body = text ? JSON.parse(text) : null; } catch { body = { raw: text }; }
  return { status: res.status, body };
}
let res = await rpc(minted.url, "initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "smoke", version: "0" } });
check(res.status === 200 && res.body.result?.serverInfo?.name === "TouchTips", `initialize (${res.status})`);
check(/Quote the "when" field/.test(res.body.result?.instructions ?? ""), "server instructions delivered");
res = await rpc(minted.url, "tools/list", {});
const toolNames = (res.body.result?.tools ?? []).map((t) => t.name).sort();
check(JSON.stringify(toolNames) === JSON.stringify(["get_person", "list_meetings", "search_people"]), `tools: ${toolNames.join(", ")}`);
res = await rpc(minted.url, "tools/call", { name: "search_people", arguments: { query: "jose" } });
const found = res.body.result?.structuredContent?.people ?? [];
check(found.length === 1 && found[0].name === "José Álvarez" && found[0].meetings[0].when === "2022" && found[0].meetings[0].confidence === "estimated", `search_people → ${found[0]?.name} met ${found[0]?.meetings[0]?.when}`);
res = await rpc(minted.url, "tools/call", { name: "get_person", arguments: { id: "p-sam" } });
const sam = res.body.result?.structuredContent?.person;
check(sam?.meetings[0]?.when === "March 14, 2024 at 3:12 PM" && sam.meetings[0].place?.name === "Brooklyn Boulders", `get_person → ${sam?.meetings[0]?.when} at ${sam?.meetings[0]?.place?.name}`);
res = await rpc(minted.url, "tools/call", { name: "list_meetings", arguments: { place: "boulders" } });
check(res.body.result?.structuredContent?.meetings?.length === 1, "list_meetings filters by place");
res = await rpc(`${BASE}/c/${"x".repeat(43)}/mcp`, "tools/list", {});
check(res.status === 404, "unknown connector → 404");
r = await fetch(`${BASE}/v1/keys`, { headers: device });
({ keys } = await r.json());
check(keys.find((k) => k.id === minted.id)?.lastUsedAt, "last used is recorded");

// 4. Disconnect Claude from the phone; its URL dies immediately. Grok still works.
r = await fetch(`${BASE}/v1/keys/${minted.id}`, { method: "DELETE", headers: device });
check(r.status === 200, "connector revoked");
res = await rpc(minted.url, "tools/list", {});
check(res.status === 404, "revoked URL rejected");
res = await rpc(second.url, "tools/list", {});
check(res.status === 200, "other connector unaffected");

// 5. Delete everything.
r = await fetch(`${BASE}/v1/account`, { method: "DELETE", headers: device });
check(r.status === 204, "account deleted");
res = await rpc(second.url, "tools/list", {});
check(res.status === 404, "every connector gone");
r = await fetch(`${BASE}/v1/keys`, { headers: device });
check((await r.json()).keys.length === 0, "no keys remain");

// 6. Universal link plumbing.
const aasa = await (await fetch(`${BASE}/.well-known/apple-app-site-association`)).json();
check(aasa.applinks.details[0].components.some((c) => c["/"] === "/connect/*"), "apple-app-site-association covers /connect/*");

console.log("\nsmoke passed");
