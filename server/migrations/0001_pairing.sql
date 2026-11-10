-- One row per pairing attempt. The browser polls `status`; the phone claims the code.
CREATE TABLE pairing (
  code TEXT PRIMARY KEY,
  auth_request TEXT NOT NULL,       -- AuthRequest JSON from parseAuthRequest
  client_name TEXT NOT NULL,
  created_at INTEGER NOT NULL,      -- unix ms
  status TEXT NOT NULL DEFAULT 'pending',  -- pending | approved | denied
  redirect_to TEXT                  -- set once approved or denied
);
