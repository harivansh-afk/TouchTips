import { withDevice } from "$lib/server/device";
import { userIdForHash } from "$lib/server/identity";
import { json } from "$lib/server/json";
import { revokePairedClient } from "$lib/server/store";
import type { RequestHandler } from "./$types";

/** Revoke one client. */
export const DELETE: RequestHandler = async (event) => {
  const clientId = decodeURIComponent(event.params.id);
  return withDevice(async (userHash) => {
    const userId = await userIdForHash(userHash);
    if (userId) await revokePairedClient(userId, clientId);
    return json({ ok: true });
  })(event);
};
