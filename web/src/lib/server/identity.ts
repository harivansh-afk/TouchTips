// The phone's credential. A random device key, sent as a bearer token on every /v1 call.
// The server stores only its hash (the user) and uses the key itself to unwrap the user's data key.

import { sha256 } from "./crypto";

const DEVICE_KEY = /^Bearer\s+(tt_[A-Za-z0-9_-]{43})$/;
export const CLIENT_KEY = /^[A-Za-z0-9_-]{43}$/;
export const PUBLIC_ID = /^[A-Za-z0-9_-]{22}$/;

export interface Device {
  key: string;
  userHash: string;
}

/** The device behind a request, or null when the Authorization header is absent or malformed. */
export function deviceFromRequest(request: Request): Device | null {
  const m = DEVICE_KEY.exec(request.headers.get("authorization") ?? "");
  return m ? { key: m[1], userHash: sha256(m[1]) } : null;
}
