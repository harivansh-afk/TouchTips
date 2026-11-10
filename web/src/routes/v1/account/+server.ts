import { withDevice } from "$lib/server/device";
import { userIdForHash } from "$lib/server/identity";
import { deleteSnapshot, deleteUser } from "$lib/server/store";
import type { RequestHandler } from "./$types";

/** Forget this phone entirely: snapshot, user, every grant. */
export const DELETE: RequestHandler = withDevice(async (userHash) => {
  const userId = await userIdForHash(userHash);
  if (userId) await deleteUser(userId);
  await deleteSnapshot(userHash);
  return new Response(null, { status: 204 });
});
