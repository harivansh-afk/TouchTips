import { json } from "$lib/server/json";
import { getPairing } from "$lib/server/store";
import type { RequestHandler } from "./$types";

/** Polled by the pairing page. */
export const GET: RequestHandler = async ({ params }) => {
  const row = await getPairing(params.code);
  if (!row) return json({ status: "expired" });
  if (row.status === "pending") return json({ status: "pending" });
  return json({ status: row.status, redirectTo: row.redirect_to });
};
