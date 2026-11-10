// The phone, holding the device key, lets the client in. Mechanically: sign the browser in as this
// phone's user with a magic link, whose callback replays the original authorize request.
import { getAuth, pendingMagicTokens } from "$lib/server/auth";
import { withDevice } from "$lib/server/device";
import { emailForHash } from "$lib/server/identity";
import { json } from "$lib/server/json";
import { finishPairing, getPairing } from "$lib/server/store";
import type { RequestHandler } from "./$types";

export const POST: RequestHandler = async (event) =>
  withDevice(async (userHash) => {
    const row = await getPairing(event.params.code);
    if (!row || row.status !== "pending") return json({ error: "unknown or expired code" }, 404);

    const email = emailForHash(userHash);
    const callbackURL = `/api/auth/oauth2/authorize?${row.authorize_query}`;
    pendingMagicTokens.delete(email);
    await getAuth().api.signInMagicLink({ body: { email, name: "TouchTips", callbackURL }, headers: new Headers() });
    const token = pendingMagicTokens.get(email);
    pendingMagicTokens.delete(email);
    if (!token) return json({ error: "could not start sign-in" }, 500);

    const redirectTo = `/api/auth/magic-link/verify?${new URLSearchParams({ token, callbackURL })}`;
    await finishPairing(row.code, "approved", redirectTo);
    return json({ clientName: row.client_name });
  })(event);
