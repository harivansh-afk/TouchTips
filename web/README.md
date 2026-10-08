# TouchTips web

SvelteKit home, support, and privacy pages for touchtips.app, prerendered with adapter-static. Shared navigation and styling live in `src/routes/+layout.svelte` and `src/styles.css`. The app icon supplies the site branding and browser icons in `static/`. The home page includes the demo video and links to TestFlight and the GitHub repository.

## Development

```sh
bun install --frozen-lockfile
bun run dev
bun run build
```

## Deployment

Vercel follows `main` in `harivansh-afk/TouchTips`, with `web` as the Root Directory. `vercel.json` defines the build and `build` output directory. `/ios` redirects to TestFlight.

The Swift app and packages remain independent at the repository root.
