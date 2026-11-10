import type { OAuthHelpers } from "@cloudflare/workers-oauth-provider";

export interface Env {
  OAUTH_KV: KVNamespace;
  SNAPSHOTS: R2Bucket;
  DB: D1Database;
  /** Origin MCP clients connect to, e.g. https://mcp.touchtips.app */
  PUBLIC_URL: string;
  /** Injected by OAuthProvider for the default handler. */
  OAUTH_PROVIDER: OAuthHelpers;
}

/** Stored on every grant at pairing time and handed to tools as the auth context. */
export interface Props {
  userId: string;
}

export const SCOPE = "meetings:read";
export const APPLE_APP_ID = "G2U3K77U5W.sh.harivan.touchtips";
