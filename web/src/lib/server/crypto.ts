// Every user's data is sealed under their own data key. The database holds that key only wrapped under
// secrets it never stores: the phone's device key, a live OAuth token, or a connector URL's key.
// A copy of the database alone decrypts nothing.
//
// Lookups use sha256(secret); wrapping uses HKDF(secret, label). The two never meet, so a stored
// hash says nothing about the wrapping key.

import { createCipheriv, createDecipheriv, createHash, hkdfSync, randomBytes, timingSafeEqual } from "node:crypto";

export function sha256(s: string): string {
  return createHash("sha256").update(s).digest("hex");
}

/** 256 random bits, base64url. Every credential and code is one of these. */
export function secret(): string {
  return randomBytes(32).toString("base64url");
}

export function newId(prefix = ""): string {
  return prefix + randomBytes(12).toString("base64url");
}

export function newDataKey(): Buffer {
  return randomBytes(32);
}

function kek(secretValue: string, label: string): Buffer {
  return Buffer.from(hkdfSync("sha256", secretValue, "touchtips/v1", label, 32));
}

/** AES-256-GCM. Output: base64url(iv || tag || ciphertext). `aad` binds the blob to where it's stored. */
export function seal(key: Buffer, plaintext: Buffer | string, aad: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  cipher.setAAD(Buffer.from(aad));
  const body = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), body]).toString("base64url");
}

export function open(key: Buffer, sealed: string, aad: string): Buffer {
  const raw = Buffer.from(sealed, "base64url");
  const decipher = createDecipheriv("aes-256-gcm", key, raw.subarray(0, 12));
  decipher.setAAD(Buffer.from(aad));
  decipher.setAuthTag(raw.subarray(12, 28));
  return Buffer.concat([decipher.update(raw.subarray(28)), decipher.final()]);
}

/** Wrap a data key under a secret. `label` says which kind of secret, so one can't stand in for another. */
export function wrap(dataKey: Buffer, secretValue: string, label: string): string {
  return seal(kek(secretValue, label), dataKey, label);
}

export function unwrap(wrapped: string, secretValue: string, label: string): Buffer {
  return open(kek(secretValue, label), wrapped, label);
}

/** The deployment's own key, for the minutes between a phone's Allow and the client's token exchange. */
function serverKey(): Buffer {
  const raw = process.env.TT_SERVER_KEY;
  if (!raw) throw new Error("TT_SERVER_KEY is not set");
  const key = Buffer.from(raw, "base64");
  if (key.length !== 32) throw new Error("TT_SERVER_KEY must be 32 bytes, base64");
  return key;
}

export function sealForServer(dataKey: Buffer, aad: string): string {
  return seal(serverKey(), dataKey, aad);
}

export function openForServer(sealed: string, aad: string): Buffer {
  return open(serverKey(), sealed, aad);
}

/** PKCE S256: base64url(sha256(verifier)) == challenge, compared in constant time. */
export function pkceMatches(verifier: string, challenge: string): boolean {
  if (!/^[A-Za-z0-9\-._~]{43,128}$/.test(verifier)) return false;
  const computed = Buffer.from(createHash("sha256").update(verifier).digest("base64url"));
  const expected = Buffer.from(challenge);
  return computed.length === expected.length && timingSafeEqual(computed, expected);
}
