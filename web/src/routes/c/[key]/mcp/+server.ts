// The connector URL. The key in the path is the whole credential: no OAuth, no headers.
import { CLIENT_KEY } from "$lib/server/identity";
import { json } from "$lib/server/json";
import { mcpHandlerFor } from "$lib/server/mcp";
import { userHashForClientKey } from "$lib/server/store";
import type { RequestHandler } from "./$types";

const handle: RequestHandler = async ({ params, request }) => {
  if (!CLIENT_KEY.test(params.key)) return json({ error: "unknown connector" }, 404);
  const userHash = await userHashForClientKey(params.key);
  if (!userHash) return json({ error: "unknown connector" }, 404);
  return mcpHandlerFor(userHash).fetch(request);
};

export const POST = handle;
export const GET = handle;
export const DELETE = handle;
