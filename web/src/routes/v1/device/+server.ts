// Where to send approval prompts.
import { setPushToken } from "$lib/server/account";
import { accountFor } from "$lib/server/account";
import { withDevice } from "$lib/server/device";
import { json } from "$lib/server/json";

export const PUT = withDevice(async (device, { request }) => {
  const body = (await request.json().catch(() => ({}))) as { apnsToken?: unknown; apnsEnv?: unknown };
  const token = typeof body.apnsToken === "string" && /^[0-9a-f]{64,200}$/i.test(body.apnsToken) ? body.apnsToken : null;
  const env = body.apnsEnv === "sandbox" ? "sandbox" : "production";
  const account = await accountFor(device);
  await setPushToken(account.userHash, token, env);
  return json({ ok: true });
});
