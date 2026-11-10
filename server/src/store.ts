import type { AuthRequest } from "@cloudflare/workers-oauth-provider";
import type { Env } from "./env";
import { SnapshotSchema, type Snapshot } from "./snapshot";

const MAX_SNAPSHOT_BYTES = 10 * 1024 * 1024;
export const PAIRING_TTL_MS = 10 * 60 * 1000;

function key(userId: string): string {
  return `users/${userId}.json`;
}

export async function readSnapshot(env: Env, userId: string): Promise<Snapshot | null> {
  const obj = await env.SNAPSHOTS.get(key(userId));
  if (!obj) return null;
  return SnapshotSchema.parse(await obj.json());
}

export type PutResult = "stored" | "stale" | "too-large" | "invalid";

/** Store a snapshot unless an equal-or-newer one is already there. */
export async function putSnapshot(env: Env, userId: string, body: ArrayBuffer): Promise<PutResult> {
  if (body.byteLength > MAX_SNAPSHOT_BYTES) return "too-large";
  let snapshot: Snapshot;
  try {
    snapshot = SnapshotSchema.parse(JSON.parse(new TextDecoder().decode(body)));
  } catch {
    return "invalid";
  }
  const existing = await env.SNAPSHOTS.head(key(userId));
  const prior = existing?.customMetadata?.generatedAt;
  if (prior && Date.parse(prior) >= Date.parse(snapshot.generatedAt)) return "stale";
  await env.SNAPSHOTS.put(key(userId), body, {
    httpMetadata: { contentType: "application/json" },
    customMetadata: { generatedAt: snapshot.generatedAt },
  });
  return "stored";
}

export async function deleteSnapshot(env: Env, userId: string): Promise<void> {
  await env.SNAPSHOTS.delete(key(userId));
}

export interface PairingRow {
  code: string;
  auth_request: string;
  client_name: string;
  created_at: number;
  status: "pending" | "approved" | "denied";
  redirect_to: string | null;
}

export async function createPairing(env: Env, authRequest: AuthRequest, clientName: string): Promise<string> {
  for (let attempt = 0; attempt < 5; attempt++) {
    const n = crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000;
    const code = n.toString().padStart(6, "0");
    try {
      await env.DB.prepare(
        "INSERT INTO pairing (code, auth_request, client_name, created_at) VALUES (?1, ?2, ?3, ?4)",
      )
        .bind(code, JSON.stringify(authRequest), clientName, Date.now())
        .run();
      return code;
    } catch {
      // collision with a live code; try again
    }
  }
  throw new Error("could not allocate pairing code");
}

/** The row for a code, or null when unknown or expired. */
export async function getPairing(env: Env, code: string): Promise<PairingRow | null> {
  const row = await env.DB.prepare("SELECT * FROM pairing WHERE code = ?1").bind(code).first<PairingRow>();
  if (!row) return null;
  if (Date.now() - row.created_at > PAIRING_TTL_MS) return null;
  return row;
}

export async function finishPairing(env: Env, code: string, status: "approved" | "denied", redirectTo: string): Promise<void> {
  await env.DB.prepare("UPDATE pairing SET status = ?2, redirect_to = ?3 WHERE code = ?1 AND status = 'pending'")
    .bind(code, status, redirectTo)
    .run();
}

/** Housekeeping: codes older than the TTL are dead weight. Called opportunistically. */
export async function purgePairings(env: Env): Promise<void> {
  await env.DB.prepare("DELETE FROM pairing WHERE created_at < ?1").bind(Date.now() - PAIRING_TTL_MS).run();
}
