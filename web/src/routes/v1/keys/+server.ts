// Connected apps, as the phone sees them.
import { connectorUrl } from "$lib/server/config";
import { userHashFromRequest } from "$lib/server/identity";
import { json } from "$lib/server/json";
import { CLIENTS, createClientKey, listClientKeys, type Client } from "$lib/server/store";
import type { RequestHandler } from "./$types";

export const GET: RequestHandler = async ({ request }) => {
  const userHash = userHashFromRequest(request);
  if (!userHash) return json({ error: "device key required" }, 401);
  return json({ keys: await listClientKeys(userHash) });
};

/** Mint one. The URL comes back exactly once. */
export const POST: RequestHandler = async ({ request }) => {
  const userHash = userHashFromRequest(request);
  if (!userHash) return json({ error: "device key required" }, 401);
  const body = (await request.json().catch(() => ({}))) as { client?: string; name?: string };
  const client = (CLIENTS as readonly string[]).includes(body.client ?? "") ? (body.client as Client) : "other";
  const name = (body.name ?? "").trim().slice(0, 60) || defaultName(client);
  const { row, key } = await createClientKey(userHash, client, name);
  return json({ ...row, url: connectorUrl(key) }, 201);
};

function defaultName(client: Client): string {
  return { claude: "Claude", chatgpt: "ChatGPT", "claude-code": "Claude Code", instinct: "Instinct", grok: "Grok", other: "Agent" }[client];
}
