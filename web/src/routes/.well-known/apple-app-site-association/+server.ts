import type { RequestHandler } from "./$types";

/** Lets iOS open /pair/* and /p/* in the app. */
export const GET: RequestHandler = async () =>
  new Response(
    JSON.stringify({
      applinks: { details: [{ appIDs: ["G2U3K77U5W.sh.harivan.touchtips"], components: [{ "/": "/pair/*" }, { "/": "/p/*" }] }] },
    }),
    { headers: { "content-type": "application/json" } },
  );
