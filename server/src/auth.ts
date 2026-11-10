// The phone's credential: a random key it generated once. The server only ever sees its hash.

const KEY_PATTERN = /^Bearer\s+(tt_[A-Za-z0-9_-]{40,})$/;

export async function sha256Hex(s: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** User id derived from the device key in the Authorization header, or null when absent or malformed. */
export async function userIdFromRequest(request: Request): Promise<string | null> {
  const m = KEY_PATTERN.exec(request.headers.get("authorization") ?? "");
  return m ? sha256Hex(m[1]) : null;
}
