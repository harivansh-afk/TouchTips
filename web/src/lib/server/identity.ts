// Two credentials, both random, both only ever stored as hashes.
// The device key proves a phone owns its data. A client key is one connected app's secret URL.

import { createHash, randomBytes } from "node:crypto";

const DEVICE_KEY = /^Bearer\s+(tt_[A-Za-z0-9_-]{40,})$/;
export const CLIENT_KEY = /^[A-Za-z0-9_-]{40,}$/;

export function sha256(s: string): string {
  return createHash("sha256").update(s).digest("hex");
}

/** User hash from the device key in the Authorization header, or null when absent or malformed. */
export function userHashFromRequest(request: Request): string | null {
  const m = DEVICE_KEY.exec(request.headers.get("authorization") ?? "");
  return m ? sha256(m[1]) : null;
}

export function newClientKey(): string {
  return randomBytes(32).toString("base64url");
}

export function newId(): string {
  return randomBytes(8).toString("base64url");
}
