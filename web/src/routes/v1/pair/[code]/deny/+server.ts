import { withDevice } from "$lib/server/device";
import { json } from "$lib/server/json";
import { finishPairing, getPairing } from "$lib/server/store";
import type { RequestHandler } from "./$types";

/** The phone said no; send the client an access_denied error. */
export const POST: RequestHandler = async (event) =>
  withDevice(async () => {
    const row = await getPairing(event.params.code);
    if (!row || row.status !== "pending") return json({ error: "unknown or expired code" }, 404);
    const params = new URLSearchParams(row.authorize_query);
    const redirectUri = params.get("redirect_uri");
    if (!redirectUri) return json({ error: "bad authorize request" }, 400);
    const target = new URL(redirectUri);
    target.searchParams.set("error", "access_denied");
    target.searchParams.set("error_description", "The user declined in TouchTips.");
    const state = params.get("state");
    if (state) target.searchParams.set("state", state);
    await finishPairing(row.code, "denied", target.toString());
    return json({ ok: true });
  })(event);
