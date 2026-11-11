import { withDevice } from "$lib/server/device";
import { json } from "$lib/server/json";
import { pendingRequests } from "$lib/server/oauth";

/** Sign-ins waiting for this phone's Allow. `?opened=<id>` adds the one the user opened from its sign-in page. */
export const GET = withDevice(async (device, { url }) =>
  json({ requests: await pendingRequests(device.userHash, url.searchParams.get("opened")) }),
);
