-- TouchTips' own tables. Better Auth's tables come from `auth migrate`.
CREATE TABLE IF NOT EXISTS snapshot (
  user_hash TEXT PRIMARY KEY,
  generated_at TIMESTAMPTZ NOT NULL,
  body JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pairing (
  code TEXT PRIMARY KEY,
  client_name TEXT NOT NULL,
  authorize_query TEXT NOT NULL,      -- the original /oauth2/authorize query string
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'pending',  -- pending | approved | denied
  redirect_to TEXT                     -- set once approved or denied
);
