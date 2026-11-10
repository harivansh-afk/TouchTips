// What the phone calls, authenticated by its device key.
import type { Env } from "./env";
import { deleteSnapshot, putSnapshot } from "./store";

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

/** PUT /v1/snapshot — replace everything. Idempotent; older snapshots are refused. */
export async function putSnapshotRoute(request: Request, env: Env, userId: string): Promise<Response> {
  const result = await putSnapshot(env, userId, await request.arrayBuffer());
  switch (result) {
    case "stored":
      return json({ ok: true });
    case "stale":
      return json({ error: "a newer snapshot is already stored" }, 409);
    case "too-large":
      return json({ error: "snapshot too large" }, 413);
    case "invalid":
      return json({ error: "snapshot failed validation" }, 400);
  }
}

/** GET /v1/clients — every AI client this phone has paired. */
export async function listClients(env: Env, userId: string): Promise<Response> {
  const grants = await env.OAUTH_PROVIDER.listUserGrants(userId);
  const clients = grants.items.map((g) => ({
    id: g.id,
    name: (g.metadata?.clientName as string | undefined) ?? "Unknown client",
    pairedAt: (g.metadata?.pairedAt as string | undefined) ?? new Date(g.createdAt * 1000).toISOString(),
  }));
  return json({ clients });
}

/** DELETE /v1/clients/:id — revoke one client. Its tokens stop working immediately. */
export async function revokeClient(env: Env, userId: string, grantId: string): Promise<Response> {
  await env.OAUTH_PROVIDER.revokeGrant(grantId, userId);
  return json({ ok: true });
}

/** DELETE /v1/account — forget this phone entirely: snapshot and every grant. */
export async function deleteAccount(env: Env, userId: string): Promise<Response> {
  const grants = await env.OAUTH_PROVIDER.listUserGrants(userId);
  await Promise.all(grants.items.map((g) => env.OAUTH_PROVIDER.revokeGrant(g.id, userId)));
  await deleteSnapshot(env, userId);
  return new Response(null, { status: 204 });
}
