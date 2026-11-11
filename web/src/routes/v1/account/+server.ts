import { deleteAccount } from "$lib/server/account";
import { withDevice } from "$lib/server/device";

/** Forget this phone entirely: its data, every connected app, every token. */
export const DELETE = withDevice(async (device) => {
  await deleteAccount(device.userHash);
  return new Response(null, { status: 204 });
});
