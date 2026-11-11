import { userHashFromRequest } from "$lib/server/identity";
import { json } from "$lib/server/json";
import { revokeClientKey } from "$lib/server/store";
import type { RequestHandler } from "./$types";

/** Disconnect one app. Its URL stops working at once. */
export const DELETE: RequestHandler = async ({ request, params }) => {
  const userHash = userHashFromRequest(request);
  if (!userHash) return json({ error: "device key required" }, 401);
  const removed = await revokeClientKey(userHash, params.id);
  return removed ? json({ ok: true }) : json({ error: "unknown key" }, 404);
};
