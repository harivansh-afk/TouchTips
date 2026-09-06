# TouchTips web

SvelteKit support and privacy pages for touchtips.app, prerendered with adapter-static. Shared navigation and styling live in `src/routes/+layout.svelte` and `src/styles.css`. The app icon supplies the site branding and browser icons in `static/`.

## Development

```sh
bun install --frozen-lockfile
bun run dev
bun run build
```

## Deployment

Vercel follows `main` in `harivansh-afk/TouchTips`, with `web` as the Root Directory. `vercel.json` defines the build and `build` output directory. `/support` and `/privacy` are the only pages; `/` redirects to Support.

The Swift app and packages remain independent at the repository root.
