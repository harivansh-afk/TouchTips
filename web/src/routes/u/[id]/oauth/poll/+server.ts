// The authorize page waits here for the phone's answer. Its secret proves it's the page that started the request.
import { json } from "$lib/server/json";
import { poll } from "$lib/server/oauth";
import { phone } from "$lib/server/phone";
import type { RequestHandler } from "./$types";

export const POST: RequestHandler = async ({ params, request }) => {
  const owner = await phone(params.id);
  if (!owner) return json({ status: "expired" }, 404);
  const body = (await request.json().catch(() => ({}))) as { request?: unknown; secret?: unknown };
  if (typeof body.request !== "string" || typeof body.secret !== "string") return json({ status: "expired" }, 400);
  return json(await poll(owner.publicId, body.request, body.secret));
};
