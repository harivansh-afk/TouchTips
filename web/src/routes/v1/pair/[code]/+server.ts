import { SCOPE } from "$lib/server/auth";
import { withDevice } from "$lib/server/device";
import { json } from "$lib/server/json";
import { getPairing } from "$lib/server/store";
import type { RequestHandler } from "./$types";

/** The app asks what it is about to approve. */
export const GET: RequestHandler = async (event) =>
  withDevice(async () => {
    const row = await getPairing(event.params.code);
    if (!row || row.status !== "pending") return json({ error: "unknown or expired code" }, 404);
    return json({ clientName: row.client_name, scope: [SCOPE] });
  })(event);
