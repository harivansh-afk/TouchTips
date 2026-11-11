// A connector URL, for clients without OAuth. The key in the path is the credential.
import { readSnapshot } from "$lib/server/account";
import { CLIENT_KEY } from "$lib/server/identity";
import { json } from "$lib/server/json";
import { mcpHandlerFor } from "$lib/server/mcp";
import { openClientKey } from "$lib/server/store";
import type { RequestHandler } from "./$types";

const handle: RequestHandler = async ({ params, request }) => {
  if (!CLIENT_KEY.test(params.key)) return json({ error: "unknown connector" }, 404);
  const opened = await openClientKey(params.key);
  if (!opened) return json({ error: "unknown connector" }, 404);
  return mcpHandlerFor(() => readSnapshot(opened.userHash, opened.dataKey)).fetch(request);
};

export const POST = handle;
export const GET = handle;
export const DELETE = handle;
