-- TouchTips' tables. Idempotent.
CREATE TABLE IF NOT EXISTS snapshot (
  user_hash TEXT PRIMARY KEY,
  generated_at TIMESTAMPTZ NOT NULL,
  body JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One per connected client. The key itself is never stored, only its hash.
CREATE TABLE IF NOT EXISTS client_key (
  id TEXT PRIMARY KEY,
  key_hash TEXT NOT NULL UNIQUE,
  user_hash TEXT NOT NULL,
  client TEXT NOT NULL,              -- claude | chatgpt | claude-code | cursor | vscode | other
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS client_key_user ON client_key (user_hash);

-- Left over from the OAuth version; nothing reads them any more.
DROP TABLE IF EXISTS "oauthClientAssertion", "oauthConsent", "oauthAccessToken", "oauthRefreshToken",
  "oauthClientResource", "oauthResource", "oauthClient", "jwks", "verification", "account", "session", "user", pairing;
