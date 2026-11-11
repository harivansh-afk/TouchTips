import { accountFor } from "$lib/server/account";
import { withDevice } from "$lib/server/device";
import { json } from "$lib/server/json";
import { decide } from "$lib/server/oauth";

/** Allow (with the number the user picked from the sign-in page) or deny. A wrong number denies. */
export const POST = withDevice(async (device, { request, params }) => {
  const body = (await request.json().catch(() => ({}))) as { allow?: unknown; number?: unknown };
  if (typeof body.allow !== "boolean") return json({ error: "allow must be true or false" }, 400);
  const number = typeof body.number === "number" && Number.isInteger(body.number) ? body.number : null;
  if (body.allow && number === null) return json({ error: "allowing needs the number from the sign-in page" }, 400);
  const outcome = await decide(await accountFor(device), params.id!, body.allow, number);
  return outcome === "gone" ? json({ error: "no such request, or it expired" }, 404) : json({ outcome });
});
