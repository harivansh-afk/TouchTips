import { query } from "./db";
import { SnapshotSchema, type Snapshot } from "./snapshot";

const MAX_SNAPSHOT_BYTES = 10 * 1024 * 1024;
export const PAIRING_TTL_MINUTES = 10;

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

export async function deleteSnapshot(userHash: string): Promise<void> {
  await query("DELETE FROM snapshot WHERE user_hash = $1", [userHash]);
}

export interface PairingRow {
  code: string;
  client_name: string;
  authorize_query: string;
  status: "pending" | "approved" | "denied";
  redirect_to: string | null;
}

export async function createPairing(clientName: string, authorizeQuery: string): Promise<string> {
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = String(Math.floor(Math.random() * 1_000_000)).padStart(6, "0");
    const rows = await query<{ code: string }>(
      "INSERT INTO pairing (code, client_name, authorize_query) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING RETURNING code",
      [code, clientName, authorizeQuery],
    );
    if (rows.length) return code;
  }
  throw new Error("could not allocate pairing code");
}

/** The row for a code, or null when unknown or expired. */
export async function getPairing(code: string): Promise<PairingRow | null> {
  const rows = await query<PairingRow>(
    `SELECT code, client_name, authorize_query, status, redirect_to FROM pairing
     WHERE code = $1 AND created_at > now() - make_interval(mins => $2)`,
    [code, PAIRING_TTL_MINUTES],
  );
  return rows[0] ?? null;
}

export async function finishPairing(code: string, status: "approved" | "denied", redirectTo: string): Promise<void> {
  await query("UPDATE pairing SET status = $2, redirect_to = $3 WHERE code = $1 AND status = 'pending'", [code, status, redirectTo]);
  await query("DELETE FROM pairing WHERE created_at < now() - make_interval(mins => $1)", [PAIRING_TTL_MINUTES]);
}

export interface PairedClient {
  id: string;
  name: string;
  pairedAt: string;
}

/** Clients a phone has approved: one per OAuth consent. */
export async function listPairedClients(userId: string): Promise<PairedClient[]> {
  return query<PairedClient>(
    `SELECT c."clientId" AS id, COALESCE(cl.name, 'Unknown client') AS name, c."createdAt" AS "pairedAt"
     FROM "oauthConsent" c JOIN "oauthClient" cl ON cl."clientId" = c."clientId"
     WHERE c."userId" = $1 ORDER BY c."createdAt" DESC`,
    [userId],
  );
}

/** Forget a client: its consent and every token. Outstanding access tokens die within 15 minutes. */
export async function revokePairedClient(userId: string, clientId: string): Promise<void> {
  await query('DELETE FROM "oauthRefreshToken" WHERE "userId" = $1 AND "clientId" = $2', [userId, clientId]);
  await query('DELETE FROM "oauthAccessToken" WHERE "userId" = $1 AND "clientId" = $2', [userId, clientId]);
  await query('DELETE FROM "oauthConsent" WHERE "userId" = $1 AND "clientId" = $2', [userId, clientId]);
}

/** Delete the Better Auth user; tokens, consents and sessions cascade. */
export async function deleteUser(userId: string): Promise<void> {
  await query('DELETE FROM "user" WHERE id = $1', [userId]);
}
