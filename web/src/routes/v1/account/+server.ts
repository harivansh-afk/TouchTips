import { userHashFromRequest } from "$lib/server/identity";
import { json } from "$lib/server/json";
import { deleteAccount } from "$lib/server/store";
import type { RequestHandler } from "./$types";

/** Forget this phone entirely: snapshot and every connected app. */
export const DELETE: RequestHandler = async ({ request }) => {
  const userHash = userHashFromRequest(request);
  if (!userHash) return json({ error: "device key required" }, 401);
  await deleteAccount(userHash);
  return new Response(null, { status: 204 });
};
