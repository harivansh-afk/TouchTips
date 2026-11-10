import { json } from "$lib/server/json";
import { putSnapshot } from "$lib/server/store";
import { userHashFromRequest } from "$lib/server/identity";
import type { RequestHandler } from "./$types";

/** Replace everything. Idempotent; older snapshots are refused. */
export const PUT: RequestHandler = async ({ request }) => {
  const userHash = userHashFromRequest(request);
  if (!userHash) return json({ error: "device key required" }, 401);
  switch (await putSnapshot(userHash, await request.text())) {
    case "stored":
      return json({ ok: true });
    case "stale":
      return json({ error: "a newer snapshot is already stored" }, 409);
    case "too-large":
      return json({ error: "snapshot too large" }, 413);
    case "invalid":
      return json({ error: "snapshot failed validation" }, 400);
  }
};
