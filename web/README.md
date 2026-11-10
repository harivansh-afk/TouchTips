# TouchTips web

The site at touchtips.app, and the server that lets Claude, ChatGPT and Claude Code read a user's TouchTips meetings over MCP. One SvelteKit app on Vercel.

- **Pages**: home, connect, support, privacy. Prerendered.
- **Sync**: the phone pushes its whole dataset as one JSON snapshot to `PUT /v1/snapshot`, stored per user in Neon Postgres. Older snapshots are refused.
- **Identity**: the phone holds a random device key. The user is its SHA-256, which doubles as a Better Auth user. No sign-up.
- **Pairing**: the OAuth consent step shows a six-digit code and a universal link. The phone approves with its device key; a magic link then signs the browser in as that user and the authorization resumes on its own.
- **MCP**: `POST /mcp` with three read-only tools that cite dates at the precision the record has. Better Auth's MCP plugin is the OAuth 2.1 server (discovery, dynamic client registration, PKCE, refresh, JWT access tokens).

## Routes

| Route | Who | What |
|---|---|---|
| `/mcp` | AI client, OAuth bearer | MCP over Streamable HTTP |
| `/api/auth/oauth2/*`, `/.well-known/oauth-*` | AI client | OAuth 2.1 |
| `/connect/pair`, `/connect/consent` | Browser | Pairing page and auto-accepted consent |
| `/pair/:code`, `/pair/:code/status` | Browser | Universal link; polled status |
| `/v1/snapshot`, `/v1/account`, `/v1/clients[/:id]`, `/v1/pair/:code[/approve|/deny]` | App, device key | Sync, delete, list and revoke clients, approve pairing |
| `/.well-known/apple-app-site-association` | iOS | Universal links for `/pair/*` and `/p/*` |

Device key header: `Authorization: Bearer tt_<base64url, 32 random bytes>`.

## Development

```sh
bun install --frozen-lockfile
npx vercel link && npx vercel env pull   # DATABASE_URL and BETTER_AUTH_SECRET into .env.local
set -a; source .env.local; set +a
bun run db:migrate                        # once per database
bun run dev
bun run test                              # unit tests
bun run smoke                             # full flow against the dev server
```

## Deployment

Vercel follows `main` with `web` as the root directory. CI runs the unit tests, waits for the Vercel deployment, and runs the smoke flow against it. `/ios` redirects to TestFlight.

The Swift app and packages remain independent at the repository root.
