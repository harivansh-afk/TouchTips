import { accountFor, putSnapshot } from "$lib/server/account";
import { withDevice } from "$lib/server/device";
import { json } from "$lib/server/json";

/** Replace everything. Idempotent; older snapshots are refused. Stored sealed under the phone's data key. */
export const PUT = withDevice(async (device, { request }) => {
  switch (await putSnapshot(await accountFor(device), await request.text())) {
    case "stored":
      return json({ ok: true });
    case "stale":
      return json({ error: "a newer snapshot is already stored" }, 409);
    case "too-large":
      return json({ error: "snapshot too large" }, 413);
    case "invalid":
      return json({ error: "snapshot failed validation" }, 400);
  }
});
