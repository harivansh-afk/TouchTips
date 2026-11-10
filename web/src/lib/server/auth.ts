// Better Auth is the OAuth 2.1 authorization server. Users are phones: one per device key.
import { betterAuth } from "better-auth";
import { jwt, magicLink } from "better-auth/plugins";
import { mcp } from "@better-auth/mcp";
import { pool } from "./db";

export const SCOPE = "meetings:read";
export const SCOPES = [SCOPE, "offline_access"];

/** Origin of this deployment: the custom domain in production, the unique URL on previews. */
export const BASE_URL =
  process.env.BETTER_AUTH_URL ?? (process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : "http://localhost:5173");
export const MCP_RESOURCE = `${BASE_URL}/mcp`;

/** Magic-link tokens minted during a pairing approval, keyed by the user's email, read back in the same request. */
export const pendingMagicTokens = new Map<string, string>();

type Auth = ReturnType<typeof buildAuth>;
let instance: Auth | undefined;

/** Built on first use, not at import, so prerendering and type checks don't need the env. */
export function getAuth(): Auth {
  return (instance ??= buildAuth());
}

function buildAuth() {
  return betterAuth({
  baseURL: BASE_URL,
  secret: process.env.BETTER_AUTH_SECRET,
  database: pool,
  disabledPaths: ["/token"],
  plugins: [
    jwt({ disableSettingJwtHeader: true }),
    mcp({
      loginPage: "/connect/pair",
      consentPage: "/connect/consent",
      resource: MCP_RESOURCE,
      scopes: SCOPES,
      accessTokenExpiresIn: 15 * 60,
      allowDynamicClientRegistration: true,
      allowUnauthenticatedClientRegistration: true,
      clientRegistrationDefaultApplicationType: "infer",
    }),
    magicLink({
      expiresIn: 5 * 60,
      sendMagicLink: async ({ email, token }) => {
        pendingMagicTokens.set(email, token);
      },
    }),
  ],
});
}
