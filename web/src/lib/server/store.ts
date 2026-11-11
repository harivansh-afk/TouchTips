// Connected apps, as the phone sees them: OAuth grants, plus connector URLs for clients that can't do OAuth.
import { query } from "./db";
import { newId, secret, sha256, unwrap, wrap } from "./crypto";
import type { Account } from "./account";

export const CLIENTS = ["claude", "chatgpt", "claude-code", "instinct", "grok", "other"] as const;
export type Client = (typeof CLIENTS)[number];

/** Clients that sign in with OAuth. The rest get a connector URL. */
export const OAUTH_CLIENTS: readonly Client[] = ["claude", "chatgpt", "claude-code", "grok"];

export function asClient(value: unknown): Client {
  return (CLIENTS as readonly unknown[]).includes(value) ? (value as Client) : "other";
}

export function clientName(client: Client): string {
  return { claude: "Claude", chatgpt: "ChatGPT", "claude-code": "Claude Code", instinct: "Instinct", grok: "Grok Bot", other: "Agent" }[client];
}

export interface ConnectedApp {
  id: string;
  client: Client;
  name: string;
  createdAt: string;
  lastUsedAt: string | null;
}

const KEY_LABEL = "connector";
/** A connector URL nobody has used for this long stops working. */
const KEY_IDLE_DAYS = 90;

/** Mint a connector URL key. The plaintext is returned once and never stored.
 *  A key for the same client that was never used is replaced, so re-tapping doesn't pile up URLs. */
export async function createClientKey(account: Account, client: Client): Promise<{ app: ConnectedApp; key: string }> {
  await query("DELETE FROM client_key WHERE user_hash = $1 AND client = $2 AND last_used_at IS NULL", [account.userHash, client]);
  const key = secret();
  const rows = await query<ConnectedApp>(
    `INSERT INTO client_key (id, key_hash, user_hash, client, name, dk_wrap) VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id, client, name, created_at AS "createdAt", last_used_at AS "lastUsedAt"`,
    [newId("k_"), sha256(key), account.userHash, client, clientName(client), wrap(account.dataKey, key, KEY_LABEL)],
  );
  return { app: rows[0], key };
}

/** The owner and data key behind a connector URL key, touching last_used_at at most once a minute. */
export async function openClientKey(key: string): Promise<{ userHash: string; dataKey: Buffer } | null> {
  const rows = await query<{ user_hash: string; dk_wrap: string }>(
    `SELECT user_hash, dk_wrap FROM client_key WHERE key_hash = $1 AND dk_wrap IS NOT NULL
       AND COALESCE(last_used_at, created_at) > now() - make_interval(days => $2)`,
    [sha256(key), KEY_IDLE_DAYS],
  );
  if (!rows[0]) return null;
  await query(
    "UPDATE client_key SET last_used_at = now() WHERE key_hash = $1 AND (last_used_at IS NULL OR last_used_at < now() - interval '1 minute')",
    [sha256(key)],
  );
  return { userHash: rows[0].user_hash, dataKey: unwrap(rows[0].dk_wrap, key, KEY_LABEL) };
}

/** Grants and connector keys together, newest first. Unused keys older than a week are cleared out. */
export async function listConnected(userHash: string): Promise<ConnectedApp[]> {
  await query("DELETE FROM client_key WHERE user_hash = $1 AND last_used_at IS NULL AND created_at < now() - interval '7 days'", [userHash]);
  return query<ConnectedApp>(
    `SELECT id, client, name, created_at AS "createdAt", last_used_at AS "lastUsedAt" FROM client_key
     WHERE user_hash = $1 AND dk_wrap IS NOT NULL
     UNION ALL
     SELECT id, client, name, created_at AS "createdAt", last_used_at AS "lastUsedAt" FROM oauth_grant WHERE user_hash = $1
     ORDER BY "createdAt" DESC`,
    [userHash],
  );
}

/** Disconnect one app. Its tokens or URL stop working at once. */
export async function revokeConnected(userHash: string, id: string): Promise<boolean> {
  const grant = await query<{ id: string }>("DELETE FROM oauth_grant WHERE user_hash = $1 AND id = $2 RETURNING id", [userHash, id]);
  if (grant.length) return true;
  const key = await query<{ id: string }>("DELETE FROM client_key WHERE user_hash = $1 AND id = $2 RETURNING id", [userHash, id]);
  return key.length > 0;
}
