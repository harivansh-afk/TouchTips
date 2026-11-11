// A phone's account and its sealed data.
import { randomBytes } from "node:crypto";
import { query } from "./db";
import { newDataKey, open, seal, unwrap, wrap } from "./crypto";
import type { Device } from "./identity";
import { SnapshotSchema, type Snapshot } from "./snapshot";

const MAX_SNAPSHOT_BYTES = 10 * 1024 * 1024;
export const DEVICE_LABEL = "device";

export interface Account {
  userHash: string;
  publicId: string;
  dataKey: Buffer;
}

/** The phone's account, created on first contact. Unwrapping with the presented key proves it's the owner's. */
export async function accountFor(device: Device): Promise<Account> {
  let rows = await query<{ public_id: string; dk_device: string }>(
    "SELECT public_id, dk_device FROM account WHERE user_hash = $1",
    [device.userHash],
  );
  if (!rows.length) {
    const dataKey = newDataKey();
    await query(
      "INSERT INTO account (user_hash, public_id, dk_device) VALUES ($1, $2, $3) ON CONFLICT (user_hash) DO NOTHING",
      [device.userHash, randomBytes(16).toString("base64url"), wrap(dataKey, device.key, DEVICE_LABEL)],
    );
    rows = await query("SELECT public_id, dk_device FROM account WHERE user_hash = $1", [device.userHash]);
  }
  return {
    userHash: device.userHash,
    publicId: rows[0].public_id,
    dataKey: unwrap(rows[0].dk_device, device.key, DEVICE_LABEL),
  };
}

export async function userHashForPublicId(publicId: string): Promise<string | null> {
  const rows = await query<{ user_hash: string }>("SELECT user_hash FROM account WHERE public_id = $1", [publicId]);
  return rows[0]?.user_hash ?? null;
}

export type PutResult = "stored" | "stale" | "too-large" | "invalid";

/** Store a snapshot unless an equal-or-newer one is already there. */
export async function putSnapshot(account: Account, raw: string): Promise<PutResult> {
  if (Buffer.byteLength(raw) > MAX_SNAPSHOT_BYTES) return "too-large";
  let snapshot: Snapshot;
  try {
    snapshot = SnapshotSchema.parse(JSON.parse(raw));
  } catch {
    return "invalid";
  }
  const sealed = seal(account.dataKey, JSON.stringify(snapshot), `vault:${account.userHash}`);
  const rows = await query<{ user_hash: string }>(
    `INSERT INTO vault (user_hash, generated_at, sealed, updated_at) VALUES ($1, $2, $3, now())
     ON CONFLICT (user_hash) DO UPDATE SET generated_at = EXCLUDED.generated_at, sealed = EXCLUDED.sealed, updated_at = now()
     WHERE vault.generated_at < EXCLUDED.generated_at
     RETURNING user_hash`,
    [account.userHash, snapshot.generatedAt, sealed],
  );
  return rows.length ? "stored" : "stale";
}

export async function readSnapshot(userHash: string, dataKey: Buffer): Promise<Snapshot | null> {
  const rows = await query<{ sealed: string }>("SELECT sealed FROM vault WHERE user_hash = $1", [userHash]);
  if (!rows[0]) return null;
  return SnapshotSchema.parse(JSON.parse(open(dataKey, rows[0].sealed, `vault:${userHash}`).toString("utf8")));
}

/** The next ten minutes: approval prompts for this client may be pushed to the phone. */
export async function openWindow(userHash: string, client: string): Promise<void> {
  await query("UPDATE account SET window_client = $2, window_until = now() + interval '10 minutes' WHERE user_hash = $1", [
    userHash,
    client,
  ]);
}

export async function setPushToken(userHash: string, token: string | null, env: "sandbox" | "production"): Promise<void> {
  await query("UPDATE account SET apns_token = $2, apns_env = $3 WHERE user_hash = $1", [userHash, token, env]);
}

/** Forget a phone entirely: its data, every grant and token, every connector URL. */
export async function deleteAccount(userHash: string): Promise<void> {
  await query("DELETE FROM client_key WHERE user_hash = $1", [userHash]);
  await query("DELETE FROM account WHERE user_hash = $1", [userHash]);
}
