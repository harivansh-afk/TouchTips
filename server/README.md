# TouchTips server

One Cloudflare Worker that lets AI clients (Claude, ChatGPT, Claude Code) read a user's TouchTips meetings over MCP.

- **Sync**: the phone pushes its whole dataset as one JSON snapshot. Stored per user in R2. Older snapshots are refused.
- **Identity**: the phone holds a random device key. The user id is its SHA-256. No sign-up, no accounts.
- **Pairing**: the OAuth consent page shows a six-digit code and a universal link. The phone approves with its device key.
- **MCP**: three read-only tools that cite dates at the precision the record has.

## Routes

| Route | Who | What |
|---|---|---|
| `POST /mcp` | AI client, OAuth bearer | MCP over Streamable HTTP |
| `GET /authorize`, `POST /oauth/token`, `POST /oauth/register`, `/.well-known/oauth-*` | AI client | OAuth 2.1 with PKCE and dynamic client registration |
| `GET /pair/:code` | Browser | Universal link; app opens it, Safari shows an install page |
| `GET /pair/:code/status` | Browser | Polled by the pairing page |
| `PUT /v1/snapshot` | App, device key | Replace the user's data |
| `GET /v1/pair/:code`, `POST /v1/pair/:code/approve`, `POST /v1/pair/:code/deny` | App, device key | Approve or decline a pairing |
| `GET /v1/clients`, `DELETE /v1/clients/:id` | App, device key | List and revoke paired clients |
| `DELETE /v1/account` | App, device key | Delete snapshot and every grant |
| `GET /.well-known/apple-app-site-association` | iOS | Universal links for `/pair/*` and `/p/*` |

Device key header: `Authorization: Bearer tt_<base64url, 32 random bytes>`.

## Local

```sh
npm install
npx wrangler d1 migrations apply touchtips --local
npm run dev            # http://localhost:8788
npm test               # unit tests
npm run smoke          # full flow against the dev server
```

## Deploy (once)

Needs a Cloudflare API token with Workers Scripts, Workers KV, D1, R2 and DNS (touchtips.app) edit rights in `CLOUDFLARE_API_TOKEN`.

```sh
npx wrangler kv namespace create OAUTH_KV      # put the id in wrangler.jsonc (both places)
npx wrangler d1 create touchtips               # put the id in wrangler.jsonc (both places)
npx wrangler r2 bucket create touchtips-snapshots
npx wrangler d1 migrations apply touchtips --env production --remote
npx wrangler deploy --env production
```

The custom domain `mcp.touchtips.app` is created by the deploy. Then:

```sh
claude mcp add --transport http touchtips https://mcp.touchtips.app/mcp
```
