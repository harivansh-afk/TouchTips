# TouchTips web

The site at touchtips.app, and the server that lets Claude, ChatGPT and Claude Code read a user's TouchTips meetings over MCP. One SvelteKit app on Vercel.

- **Pages**: home, connect, support, privacy. Prerendered.
- **Sync**: the phone pushes its whole dataset as one JSON snapshot to `PUT /v1/snapshot`, stored per user in Neon Postgres. Older snapshots are refused.
- **Identity**: the phone holds a random device key. The user is its SHA-256. No sign-up.
- **Connecting**: the app mints one secret URL per client (`/c/<key>/mcp`). The URL is the whole credential: no OAuth, no headers. Keys are stored hashed, revocable from the app, with last-used times.
- **MCP**: three read-only tools that cite dates at the precision the record has.

## Routes

| Route | Who | What |
|---|---|---|
| `/c/:key/mcp` | AI client | MCP over Streamable HTTP; the key is the credential |
| `/connect`, `/connect/:client` | Browser | Per-client steps; on a phone with the app, a universal link into Connect |
| `/v1/snapshot`, `/v1/keys[/:id]`, `/v1/account` | App, device key | Sync, mint and list and revoke keys, delete |
| `/.well-known/apple-app-site-association` | iOS | Universal links for `/connect/*` and `/p/*` |

Device key header: `Authorization: Bearer tt_<base64url, 32 random bytes>`.

## Development

```sh
bun install --frozen-lockfile
npx vercel link && npx vercel env pull   # DATABASE_URL into .env.local
set -a; source .env.local; set +a
bun run db:migrate                        # once per database
bun run dev
bun run test                              # unit tests
bun run smoke                             # full flow against the dev server
```

## Deployment

Vercel follows `main` with `web` as the root directory. CI runs the unit tests, waits for the Vercel deployment, and runs the smoke flow against it. `/ios` redirects to TestFlight.

The Swift app and packages remain independent at the repository root.
