import { withDevice } from "$lib/server/device";
import { userIdForHash } from "$lib/server/identity";
import { json } from "$lib/server/json";
import { listPairedClients } from "$lib/server/store";
import type { RequestHandler } from "./$types";

/** Every AI client this phone has paired. */
export const GET: RequestHandler = withDevice(async (userHash) => {
  const userId = await userIdForHash(userHash);
  return json({ clients: userId ? await listPairedClients(userId) : [] });
});
