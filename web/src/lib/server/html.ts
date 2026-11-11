// Tiny pages, no framework, so they load instantly in a client's sign-in sheet. Same ground and type as the app.
import { randomBytes } from "node:crypto";

export function escape(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

const STYLE = `
  @font-face { font-family: "Instrument Serif"; font-style: italic; src: url("/fonts/InstrumentSerif-Italic.ttf") format("truetype"); }
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; background: #000; color: #f2f2f2; font: 17px/1.45 -apple-system, system-ui, sans-serif;
         display: grid; place-items: center; min-height: 100dvh; padding: 28px; }
  main { width: 100%; max-width: 380px; text-align: center; }
  h1 { font: italic 400 38px/1.1 "Instrument Serif", Georgia, serif; margin: 0 0 14px; letter-spacing: -.01em; }
  p { color: rgba(255,255,255,.62); margin: 0 0 22px; }
  .who { color: #fff; }
  .number { font: italic 400 96px/1 "Instrument Serif", Georgia, serif; margin: 6px 0 28px; letter-spacing: .02em; }
  .pulse { width: 12px; height: 12px; border-radius: 50%; background: #fff; margin: 0 auto 26px; animation: p 1.6s ease-in-out infinite; }
  @keyframes p { 0%,100% { opacity: .2; transform: scale(.8) } 50% { opacity: 1; transform: scale(1) } }
  a.button { display: block; background: #fff; color: #000; text-decoration: none; font-weight: 600;
             padding: 15px; border-radius: 999px; margin: 0 0 12px; }
  .small { font-size: 14px; color: rgba(255,255,255,.45); }
`;

const SECURITY = {
  "content-type": "text/html; charset=utf-8",
  "cache-control": "no-store",
  "x-frame-options": "DENY",
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
};

export function page(title: string, body: string, script = ""): Response {
  const nonce = randomBytes(16).toString("base64");
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex">
<title>${escape(title)}</title><style nonce="${nonce}">${STYLE}</style></head>
<body><main>${body}</main>${script ? `<script nonce="${nonce}">${script}</script>` : ""}</body></html>`;
  return new Response(html, {
    headers: {
      ...SECURITY,
      "content-security-policy": `default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}'; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'`,
    },
  });
}

export function messagePage(title: string, text: string, link?: { href: string; label: string }): Response {
  const body = `<h1>${escape(title)}</h1><p>${escape(text)}</p>${
    link ? `<a class="button" href="${escape(link.href)}">${escape(link.label)}</a>` : ""
  }`;
  return page(title, body);
}
