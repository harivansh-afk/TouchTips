// The phone's credential is a random key it generated once. We only ever see its hash,
// which doubles as the Better Auth user's email so OAuth tokens map back to the phone.
import { createHash } from "node:crypto";
import { query } from "./db";

const KEY_PATTERN = /^Bearer\s+(tt_[A-Za-z0-9_-]{40,})$/;
const EMAIL_DOMAIN = "device.touchtips.app";

export function emailForHash(hash: string): string {
  return `${hash}@${EMAIL_DOMAIN}`;
}

export function hashFromEmail(email: string): string | null {
  const [hash, domain] = email.split("@");
  return domain === EMAIL_DOMAIN && /^[0-9a-f]{64}$/.test(hash) ? hash : null;
}

/** User hash from the device key in the Authorization header, or null when absent or malformed. */
export function userHashFromRequest(request: Request): string | null {
  const m = KEY_PATTERN.exec(request.headers.get("authorization") ?? "");
  return m ? createHash("sha256").update(m[1]).digest("hex") : null;
}

/** The Better Auth user id for a phone, or null when the phone never paired. */
export async function userIdForHash(hash: string): Promise<string | null> {
  const rows = await query<{ id: string }>('SELECT id FROM "user" WHERE email = $1', [emailForHash(hash)]);
  return rows[0]?.id ?? null;
}

export async function hashForUserId(userId: string): Promise<string | null> {
  const rows = await query<{ email: string }>('SELECT email FROM "user" WHERE id = $1', [userId]);
  return rows[0] ? hashFromEmail(rows[0].email) : null;
}
