// Tiny pages. No framework: a pairing page should load instantly on a phone.

export function escape(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

const STYLE = `
  :root { color-scheme: light dark; --fg: #111; --muted: #666; --bg: #fff; --card: #f4f4f5; --accent: #0a84ff; }
  @media (prefers-color-scheme: dark) { :root { --fg: #f2f2f2; --muted: #9a9a9a; --bg: #000; --card: #1c1c1e; } }
  * { box-sizing: border-box; }
  body { margin: 0; font-family: -apple-system, system-ui, sans-serif; background: var(--bg); color: var(--fg);
         display: grid; place-items: center; min-height: 100dvh; padding: 24px; }
  main { width: 100%; max-width: 360px; text-align: center; }
  h1 { font-size: 22px; margin: 0 0 8px; }
  p { color: var(--muted); margin: 0 0 20px; line-height: 1.4; }
  .code { font-variant-numeric: tabular-nums; letter-spacing: .25em; font-size: 40px; font-weight: 600;
          background: var(--card); border-radius: 14px; padding: 18px 0; margin: 0 0 20px; }
  a.button { display: block; background: var(--accent); color: #fff; text-decoration: none; font-weight: 600;
             padding: 14px; border-radius: 12px; margin-bottom: 12px; }
  a.plain { color: var(--accent); text-decoration: none; font-size: 15px; }
  .small { font-size: 13px; }
`;

export function page(title: string, body: string, script = ""): Response {
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${escape(title)}</title>
<style>${STYLE}</style></head><body><main>${body}</main>${script ? `<script>${script}</script>` : ""}</body></html>`;
  return new Response(html, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } });
}

export function pairingPage(opts: { code: string; clientName: string; openUrl: string; appStoreUrl: string }): Response {
  const body = `
    <h1>Connect ${escape(opts.clientName)} to TouchTips</h1>
    <p>Open TouchTips on your iPhone and approve this code. On this phone, the button does it.</p>
    <div class="code" aria-label="Pairing code">${escape(opts.code)}</div>
    <a class="button" href="${escape(opts.openUrl)}">Open TouchTips</a>
    <p class="small" id="status">Waiting for approval…</p>
    <p class="small">Don't have TouchTips? <a class="plain" href="${escape(opts.appStoreUrl)}">Get it on the App Store</a></p>`;
  const script = `
    const el = document.getElementById('status');
    async function poll() {
      try {
        const r = await fetch('/pair/${opts.code}/status', { cache: 'no-store' });
        const j = await r.json();
        if (j.redirectTo) { el.textContent = 'Approved. Returning to ${escape(opts.clientName)}…'; location.replace(j.redirectTo); return; }
        if (j.status === 'expired') { el.textContent = 'This code expired. Go back and try again.'; return; }
      } catch {}
      setTimeout(poll, 1500);
    }
    poll();`;
  return page("Connect to TouchTips", body, script);
}

export function messagePage(title: string, text: string, link?: { href: string; label: string }): Response {
  const body = `<h1>${escape(title)}</h1><p>${escape(text)}</p>${
    link ? `<a class="button" href="${escape(link.href)}">${escape(link.label)}</a>` : ""
  }`;
  return page(title, body);
}
