# TouchTips web

Support and privacy pages for touchtips.app. Static HTML and a shared stylesheet; no dependencies or build step.

- `/support` — contact and help
- `/privacy` — privacy policy
- `/` redirects to `/support`; there is no landing page.

## Vercel

Connect `harivansh-afk/TouchTips`, set **Root Directory** to `web`, and use the **Other** framework preset. `vercel.json` defines the `public` output directory and routes. Production follows `main`.

The iOS app and Swift packages remain at the repository root. Web changes are confined to this directory.
