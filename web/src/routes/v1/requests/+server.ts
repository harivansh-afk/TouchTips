import { withDevice } from "$lib/server/device";
import { json } from "$lib/server/json";
import { pendingRequests } from "$lib/server/oauth";

/** Sign-ins waiting for this phone's Allow. */
export const GET = withDevice(async (device) => json({ requests: await pendingRequests(device.userHash) }));
