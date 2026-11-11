import { accountFor } from "$lib/server/account";
import { withDevice } from "$lib/server/device";
import { json } from "$lib/server/json";
import { decide } from "$lib/server/oauth";

/** Allow or deny one sign-in. Allow is what lets a client's token open this phone's data. */
export const POST = withDevice(async (device, { request, params }) => {
  const body = (await request.json().catch(() => ({}))) as { allow?: unknown };
  if (typeof body.allow !== "boolean") return json({ error: "allow must be true or false" }, 400);
  const ok = await decide(await accountFor(device), params.id!, body.allow);
  return ok ? json({ ok: true }) : json({ error: "no such request, or it expired" }, 404);
});
