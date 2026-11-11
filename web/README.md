# TouchTips web

The site at touchtips.app, and the server that lets Claude, ChatGPT and Claude Code read a user's TouchTips meetings over MCP. One SvelteKit app on Vercel.

- **Pages**: home, connect, support, privacy. Prerendered.
- **Sync**: the phone pushes its whole dataset as one JSON snapshot to `PUT /v1/snapshot`. Older snapshots are refused.
- **Identity**: the phone holds a random device key (Keychain). The user is its SHA-256. No sign-up.
- **Encryption at rest**: each phone's data is sealed (AES-256-GCM) under its own data key. The database stores that key only wrapped under secrets it never holds: the device key, a live OAuth token, or a connector URL's key. A copy of the database decrypts nothing.
- **Connecting** follows the MCP authorization spec: OAuth 2.1 with PKCE (S256 only), protected resource metadata (RFC 9728), authorization server metadata (RFC 8414), dynamic client registration (RFC 7591), resource indicators (RFC 8707), `iss` in the response (RFC 9207). Each phone is its own issuer, `/u/<public id>`; the public id names the URL and is not a credential.
- **Approval** replaces a login page: the client's sign-in pushes "Allow Claude?" to the phone (APNs), and only Allow there, which needs the device key, lets a token open the data. Prompts are pushed only in the ten minutes after the user taps that client in the app. The phone names the client only when the sign-in returns to that client's own site; otherwise it shows the host.
- **Tokens**: access tokens last an hour; refresh tokens rotate, and a replayed one ends the whole grant. A reused code revokes what it got. Everything is stored hashed and revocable from the app.
- **Connector URLs** (`/c/<key>/mcp`) remain only for clients that can't do OAuth (Instinct, "Any agent"). The key is the credential; unused for 90 days, it stops working.
- **MCP**: three read-only tools that cite dates at the precision the record has.

## Routes

| Route | Who | What |
|---|---|---|
| `/u/:id/mcp` | AI client | MCP over Streamable HTTP; OAuth bearer token |
| `/.well-known/oauth-protected-resource/u/:id/mcp` | AI client | RFC 9728 metadata |
| `/.well-known/oauth-authorization-server/u/:id` (and the OpenID locations) | AI client | RFC 8414 metadata |
| `/oauth/register` | AI client | RFC 7591 registration, public clients only |
| `/u/:id/oauth/authorize`, `/u/:id/oauth/poll` | Browser | Waits for the phone's Allow, then redirects with the code |
| `/u/:id/oauth/token` | AI client | `authorization_code` with PKCE, `refresh_token` |
| `/c/:key/mcp` | AI client | Connector URL; the key is the credential |
| `/v1/snapshot`, `/v1/connect`, `/v1/device`, `/v1/requests[/:id]`, `/v1/keys[/:id]`, `/v1/account` | App, device key | Sync, start a connection, push token, Allow or deny, list and disconnect, delete |
| `/connect`, `/connect/:client` | Browser | Per-client steps; on a phone with the app, a universal link into Connect |
| `/.well-known/apple-app-site-association` | iOS | Universal links for `/connect/*` and `/p/*` |

Device key header: `Authorization: Bearer tt_<base64url, 32 random bytes>`.

## Environment

| Variable | What |
|---|---|
| `DATABASE_URL` | Neon Postgres |
| `PUBLIC_BASE_URL` | Production origin; previews use `VERCEL_URL` |
| `TT_SERVER_KEY` | 32 random bytes, base64. Seals a data key for the minutes between Allow and the token exchange |
| `APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID` | The `.p8` key (contents), its id, the team. Without them no prompt is pushed; Allow still works in the app |

## Development

```sh
bun install --frozen-lockfile
npx vercel link && npx vercel env pull   # DATABASE_URL into .env.local
set -a; source .env.local; set +a
bun run db:migrate                        # app.sql: idempotent, run on every schema change
bun run dev
bun run test                              # unit tests
bun run smoke                             # full OAuth flow against the dev server, playing phone and client
```

## Deployment

Vercel follows `main` with `web` as the root directory. CI runs the unit tests, waits for the Vercel deployment, and runs the smoke flow against it. `/ios` redirects to TestFlight.

Previews and production share one database, so `app.sql` stays additive: apply it before a release that needs it. Destructive steps live in their own file and run once the release is live (`node scripts/migrate-app.mjs cleanup-plaintext.sql`).

The phone side of the whole flow, with real APNs pushes, is `ConnectApprovalUITests` in the app: run the dev server with the APNs variables, then
`TEST_RUNNER_TOUCHTIPS_CLOUD_E2E=http://127.0.0.1:5199 xcodebuild test -only-testing:TouchTipsUITests/ConnectApprovalUITests` on a simulator (debug builds read `-cloudBaseURL`).

The Swift app and packages remain independent at the repository root.
