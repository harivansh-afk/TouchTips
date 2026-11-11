// The page a client's sign-in opens. No login: it asks the phone, then waits for Allow.
import { escape, messagePage, page } from "$lib/server/html";
import { authorize } from "$lib/server/oauth";
import { phone } from "$lib/server/phone";
import type { RequestHandler } from "./$types";

export const GET: RequestHandler = async ({ params, url }) => {
  const owner = await phone(params.id);
  if (!owner) return messagePage("Not found", "This TouchTips link doesn't belong to anyone. Connect again from the app.");
  const outcome = await authorize(owner.publicId, owner.userHash, url.searchParams);
  switch (outcome.kind) {
    case "error":
      return messagePage("Can't connect", outcome.message);
    case "redirect":
      return new Response(null, { status: 302, headers: { location: outcome.location, "cache-control": "no-store" } });
    case "wait":
      return waitingPage(owner.publicId, outcome);
  }
};

function waitingPage(publicId: string, o: { requestId: string; browserSecret: string; displayName: string; pushed: boolean }): Response {
  const who = `<span class="who">${escape(o.displayName)}</span>`;
  const body = o.pushed
    ? `<div class="pulse"></div><h1>Check your iPhone</h1>
       <p>TouchTips is asking if ${who} can read your people and meetings. Tap <span class="who">Allow</span>.</p>`
    : `<div class="pulse"></div><h1>Allow in TouchTips</h1>
       <p>Open TouchTips on your iPhone to let ${who} read your people and meetings.</p>`;
  const open = `<a class="button" href="touchtips://approve/${encodeURIComponent(o.requestId)}">Open TouchTips</a>
    <p class="small" id="status">This page continues by itself once you allow.</p>`;
  const script = `
    const ask = { request: ${JSON.stringify(o.requestId)}, secret: ${JSON.stringify(o.browserSecret)} };
    const endpoint = ${JSON.stringify(`/u/${publicId}/oauth/poll`)};
    async function tick() {
      try {
        const r = await fetch(endpoint, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(ask) });
        const out = await r.json();
        if (out.status === "done") { location.replace(out.location); return; }
        if (out.status === "expired") {
          document.querySelector("main").innerHTML = "<h1>Request expired</h1><p>Start again from the app you were connecting.</p>";
          return;
        }
      } catch {}
      setTimeout(tick, 1500);
    }
    setTimeout(tick, 1000);`;
  return page("Connect TouchTips", body + open, script);
}
