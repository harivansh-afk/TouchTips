// The user tapped a client in the app. Hand back this phone's MCP URL and, for ten minutes,
// let that client's sign-in push an approval prompt to the phone.
import { accountFor, closeWindow, openWindow } from "$lib/server/account";
import { withDevice } from "$lib/server/device";
import { json } from "$lib/server/json";
import { resourceUrl } from "$lib/server/oauth";
import { asClient, OAUTH_CLIENTS } from "$lib/server/store";

export const POST = withDevice(async (device, { request }) => {
  const body = (await request.json().catch(() => ({}))) as { client?: string };
  const client = asClient(body.client);
  if (!OAUTH_CLIENTS.includes(client)) return json({ error: `${client} uses a connector URL: use /v1/keys` }, 400);
  const account = await accountFor(device);
  await openWindow(account.userHash, client);
  return json({ client, url: resourceUrl(account.publicId) });
});

/** Done connecting: no more prompts until the user taps a client again. The app calls this after Allow. */
export const DELETE = withDevice(async (device) => {
  await closeWindow(device.userHash);
  return json({ ok: true });
});
