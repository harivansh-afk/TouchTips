-- Run once, after the vault release is live in production (app.sql first).
-- Removes what the old release stored: plaintext snapshots, and connector keys that can't open the vault.
-- Phones push again into the vault on their next launch; those connector URLs have to be made again.
DROP TABLE IF EXISTS snapshot;
DELETE FROM client_key WHERE dk_wrap IS NULL;
