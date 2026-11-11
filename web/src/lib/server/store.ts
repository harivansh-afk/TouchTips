import { query } from "./db";
import { newClientKey, newId, sha256 } from "./identity";
import { SnapshotSchema, type Snapshot } from "./snapshot";

const MAX_SNAPSHOT_BYTES = 10 * 1024 * 1024;

export async function readSnapshot(userHash: string): Promise<Snapshot | null> {
  const rows = await query<{ body: unknown }>("SELECT body FROM snapshot WHERE user_hash = $1", [userHash]);
  return rows[0] ? SnapshotSchema.parse(rows[0].body) : null;
}

export type PutResult = "stored" | "stale" | "too-large" | "invalid";

/** Store a snapshot unless an equal-or-newer one is already there. */
export async function putSnapshot(userHash: string, raw: string): Promise<PutResult> {
  if (Buffer.byteLength(raw) > MAX_SNAPSHOT_BYTES) return "too-large";
  let snapshot: Snapshot;
  try {
    snapshot = SnapshotSchema.parse(JSON.parse(raw));
  } catch {
    return "invalid";
  }
  const rows = await query<{ user_hash: string }>(
    `INSERT INTO snapshot (user_hash, generated_at, body, updated_at) VALUES ($1, $2, $3::jsonb, now())
     ON CONFLICT (user_hash) DO UPDATE SET generated_at = EXCLUDED.generated_at, body = EXCLUDED.body, updated_at = now()
     WHERE snapshot.generated_at < EXCLUDED.generated_at
     RETURNING user_hash`,
    [userHash, snapshot.generatedAt, JSON.stringify(snapshot)],
  );
  return rows.length ? "stored" : "stale";
}

export const CLIENTS = ["claude", "chatgpt", "claude-code", "cursor", "vscode", "other"] as const;
export type Client = (typeof CLIENTS)[number];

export interface ClientKeyRow {
  id: string;
  client: Client;
  name: string;
  createdAt: string;
  lastUsedAt: string | null;
}

/** Mint a key for one client. The plaintext is returned once and never stored. */
export async function createClientKey(userHash: string, client: Client, name: string): Promise<{ row: ClientKeyRow; key: string }> {
  const key = newClientKey();
  const id = newId();
  const rows = await query<ClientKeyRow>(
    `INSERT INTO client_key (id, key_hash, user_hash, client, name) VALUES ($1, $2, $3, $4, $5)
     RETURNING id, client, name, created_at AS "createdAt", last_used_at AS "lastUsedAt"`,
    [id, sha256(key), userHash, client, name],
  );
  return { row: rows[0], key };
}

export async function listClientKeys(userHash: string): Promise<ClientKeyRow[]> {
  return query<ClientKeyRow>(
    `SELECT id, client, name, created_at AS "createdAt", last_used_at AS "lastUsedAt"
     FROM client_key WHERE user_hash = $1 ORDER BY created_at DESC`,
    [userHash],
  );
}

export async function revokeClientKey(userHash: string, id: string): Promise<boolean> {
  const rows = await query<{ id: string }>("DELETE FROM client_key WHERE user_hash = $1 AND id = $2 RETURNING id", [userHash, id]);
  return rows.length > 0;
}

/** The owner of a client key, touching last_used_at at most once a minute. */
export async function userHashForClientKey(key: string): Promise<string | null> {
  const rows = await query<{ user_hash: string }>(
    `UPDATE client_key SET last_used_at = now()
     WHERE key_hash = $1 AND (last_used_at IS NULL OR last_used_at < now() - interval '1 minute')
     RETURNING user_hash`,
    [sha256(key)],
  );
  if (rows.length) return rows[0].user_hash;
  const fresh = await query<{ user_hash: string }>("SELECT user_hash FROM client_key WHERE key_hash = $1", [sha256(key)]);
  return fresh[0]?.user_hash ?? null;
}

/** Forget a phone entirely: its snapshot and every client key. */
export async function deleteAccount(userHash: string): Promise<void> {
  await query("DELETE FROM client_key WHERE user_hash = $1", [userHash]);
  await query("DELETE FROM snapshot WHERE user_hash = $1", [userHash]);
}
