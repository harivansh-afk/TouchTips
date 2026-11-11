import { withDevice } from "$lib/server/device";
import { json } from "$lib/server/json";
import { revokeConnected } from "$lib/server/store";

/** Disconnect one app. Its tokens or URL stop working at once. */
export const DELETE = withDevice(async (device, { params }) =>
  (await revokeConnected(device.userHash, params.id!)) ? json({ ok: true }) : json({ error: "unknown key" }, 404),
);
