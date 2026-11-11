// Connected apps, as the phone sees them, and connector URLs for clients without OAuth.
import { accountFor } from "$lib/server/account";
import { connectorUrl } from "$lib/server/config";
import { withDevice } from "$lib/server/device";
import { json } from "$lib/server/json";
import { asClient, createClientKey, listConnected, OAUTH_CLIENTS } from "$lib/server/store";

export const GET = withDevice(async (device) => json({ keys: await listConnected(device.userHash) }));

/** Mint a connector URL. Only for clients that can't sign in with OAuth. The URL comes back exactly once. */
export const POST = withDevice(async (device, { request }) => {
  const body = (await request.json().catch(() => ({}))) as { client?: string };
  const client = asClient(body.client);
  if (OAUTH_CLIENTS.includes(client)) return json({ error: `${client} signs in with OAuth: use /v1/connect` }, 400);
  const { app, key } = await createClientKey(await accountFor(device), client);
  return json({ ...app, url: connectorUrl(key) }, 201);
});
