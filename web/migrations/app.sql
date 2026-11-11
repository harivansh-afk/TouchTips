-- TouchTips' tables. Idempotent: safe to run on every deploy.
-- No secret is stored in the clear. Credentials are stored as sha256 hashes; the per-user data key is
-- stored only wrapped under secrets the database never holds (see src/lib/server/crypto.ts).

-- One per phone. user_hash = sha256(device key). public_id names the phone's MCP URL; it is not a credential.
CREATE TABLE IF NOT EXISTS account (
  user_hash TEXT PRIMARY KEY,
  public_id TEXT NOT NULL UNIQUE,
  dk_device TEXT NOT NULL,             -- data key wrapped under the device key
  apns_token TEXT,
  apns_env TEXT,                       -- sandbox | production
  window_client TEXT,                  -- the client the user just tapped in the app
  window_until TIMESTAMPTZ,            -- approval prompts are pushed only before this
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The phone's data, sealed with its data key.
CREATE TABLE IF NOT EXISTS vault (
  user_hash TEXT PRIMARY KEY REFERENCES account (user_hash) ON DELETE CASCADE,
  generated_at TIMESTAMPTZ NOT NULL,
  sealed TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Dynamically registered OAuth clients (RFC 7591). Public clients only: PKCE, no secrets.
CREATE TABLE IF NOT EXISTS oauth_client (
  client_id TEXT PRIMARY KEY,
  client_name TEXT NOT NULL,
  redirect_uris TEXT[] NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One authorization attempt, from the client's /authorize to its token exchange.
CREATE TABLE IF NOT EXISTS auth_request (
  id TEXT PRIMARY KEY,
  user_hash TEXT NOT NULL REFERENCES account (user_hash) ON DELETE CASCADE,
  client_id TEXT NOT NULL REFERENCES oauth_client (client_id) ON DELETE CASCADE,
  client TEXT NOT NULL,                -- claude | chatgpt | grok | other: what the user tapped
  display_name TEXT NOT NULL,
  redirect_uri TEXT NOT NULL,
  state TEXT,
  code_challenge TEXT NOT NULL,
  browser_hash TEXT NOT NULL,          -- sha256 of the secret only the authorize page holds
  status TEXT NOT NULL DEFAULT 'pending', -- pending | allowed | denied | issued | exchanged
  pending_dk TEXT,                     -- data key under the server key, between Allow and exchange only
  code_hash TEXT UNIQUE,
  grant_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS auth_request_user ON auth_request (user_hash);

-- One per approval. What the phone lists as a connected app and can disconnect.
CREATE TABLE IF NOT EXISTS oauth_grant (
  id TEXT PRIMARY KEY,
  user_hash TEXT NOT NULL REFERENCES account (user_hash) ON DELETE CASCADE,
  client_id TEXT NOT NULL,
  client TEXT NOT NULL,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS oauth_grant_user ON oauth_grant (user_hash);

-- Access tokens (1 hour) and refresh tokens (rotating, 60 days). Each carries the data key, wrapped under itself.
CREATE TABLE IF NOT EXISTS oauth_token (
  token_hash TEXT PRIMARY KEY,
  grant_id TEXT NOT NULL REFERENCES oauth_grant (id) ON DELETE CASCADE,
  kind TEXT NOT NULL,                  -- access | refresh
  dk_wrap TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ                  -- a refresh token is single-use; reuse revokes the grant
);
CREATE INDEX IF NOT EXISTS oauth_token_grant ON oauth_token (grant_id);

-- Connector URLs, for clients that can't do OAuth. The key in the URL is the credential.
CREATE TABLE IF NOT EXISTS client_key (
  id TEXT PRIMARY KEY,
  key_hash TEXT NOT NULL UNIQUE,
  user_hash TEXT NOT NULL,
  client TEXT NOT NULL,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS client_key_user ON client_key (user_hash);
-- Keys from before the vault have no wrap and can't open it; the server ignores them until cleanup removes them.
ALTER TABLE client_key ADD COLUMN IF NOT EXISTS dk_wrap TEXT;
