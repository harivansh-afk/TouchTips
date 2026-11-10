// Better Auth's "login page": the browser shows a six-digit code, the phone approves it.
import { BASE_URL } from "$lib/server/auth";
import { query } from "$lib/server/db";
import { pairingPage } from "$lib/server/html";
import { json } from "$lib/server/json";
import { createPairing } from "$lib/server/store";
import type { RequestHandler } from "./$types";

const APP_STORE_URL = "https://touchtips.app/ios";

export const GET: RequestHandler = async ({ url, request }) => {
  const clientId = url.searchParams.get("client_id");
  if (!clientId || !url.searchParams.get("sig")) return new Response("Missing authorization request", { status: 400 });

  // Unknown clients still get a page; Better Auth rejects them when authorization resumes.
  const rows = await query<{ name: string | null }>('SELECT name FROM "oauthClient" WHERE "clientId" = $1', [clientId]);
  const clientName = rows[0]?.name?.trim() || "this app";

  // Everything except the signature is the original authorize request; we replay it after sign-in.
  const authorize = new URLSearchParams(url.searchParams);
  for (const extra of ["sig", "ba_param", "exp", "ba_iat"]) authorize.delete(extra);
  const code = await createPairing(clientName, authorize.toString());
  const openUrl = `${BASE_URL}/pair/${code}`;

  if (request.headers.get("accept")?.includes("application/json")) return json({ code, clientName, openUrl });
  return pairingPage({ code, clientName, openUrl, appStoreUrl: APP_STORE_URL });
};
