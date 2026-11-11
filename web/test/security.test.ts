import { createHash, randomBytes } from "node:crypto";
import { beforeAll, describe, expect, it } from "vitest";
import { newDataKey, open, openForServer, pkceMatches, seal, sealForServer, secret, sha256, unwrap, wrap } from "../src/lib/server/crypto";
import { displayName, redirectAllowed } from "../src/lib/server/oauth";

beforeAll(() => {
  process.env.TT_SERVER_KEY = randomBytes(32).toString("base64");
});

describe("data key wrapping", () => {
  it("opens only with the same secret and label", () => {
    const dk = newDataKey();
    const token = secret();
    const wrapped = wrap(dk, token, "access");
    expect(unwrap(wrapped, token, "access").equals(dk)).toBe(true);
    expect(() => unwrap(wrapped, secret(), "access")).toThrow();
    expect(() => unwrap(wrapped, token, "refresh")).toThrow();
  });

  it("never stores anything the hash can open", () => {
    const dk = newDataKey();
    const token = secret();
    expect(() => unwrap(wrap(dk, token, "device"), sha256(token), "device")).toThrow();
  });

  it("binds sealed data to where it's stored", () => {
    const dk = newDataKey();
    const sealed = seal(dk, "contacts", "vault:alice");
    expect(open(dk, sealed, "vault:alice").toString()).toBe("contacts");
    expect(() => open(dk, sealed, "vault:bob")).toThrow();
    const tampered = Buffer.from(sealed, "base64url");
    tampered[tampered.length - 1] ^= 1;
    expect(() => open(dk, tampered.toString("base64url"), "vault:alice")).toThrow();
  });

  it("seals for the server under the deployment key", () => {
    const dk = newDataKey();
    expect(openForServer(sealForServer(dk, "pending:r1"), "pending:r1").equals(dk)).toBe(true);
    expect(() => openForServer(sealForServer(dk, "pending:r1"), "pending:r2")).toThrow();
  });
});

describe("PKCE", () => {
  const verifier = randomBytes(32).toString("base64url");
  const challenge = createHash("sha256").update(verifier).digest("base64url");
  it("accepts the matching verifier only", () => {
    expect(pkceMatches(verifier, challenge)).toBe(true);
    expect(pkceMatches(randomBytes(32).toString("base64url"), challenge)).toBe(false);
    expect(pkceMatches("short", challenge)).toBe(false);
    expect(pkceMatches(challenge, challenge)).toBe(false);
  });
});

describe("redirect URIs", () => {
  it("allows https, loopback http and app schemes", () => {
    expect(redirectAllowed("https://claude.ai/api/mcp/auth_callback")).toBe(true);
    expect(redirectAllowed("http://localhost:33418/callback")).toBe(true);
    expect(redirectAllowed("http://127.0.0.1:5000/cb")).toBe(true);
    expect(redirectAllowed("cursor://anysphere.cursor-mcp/oauth/callback")).toBe(true);
  });
  it("refuses everything else", () => {
    expect(redirectAllowed("http://evil.example/cb")).toBe(false);
    expect(redirectAllowed("http://localhost.evil.example/cb")).toBe(false);
    expect(redirectAllowed("javascript:alert(1)")).toBe(false);
    expect(redirectAllowed("data:text/html,hi")).toBe(false);
    expect(redirectAllowed("https://claude.ai/cb#frag")).toBe(false);
    expect(redirectAllowed("https://user:pw@claude.ai/cb")).toBe(false);
    expect(redirectAllowed("not a url")).toBe(false);
  });
});

describe("what the phone shows", () => {
  it("names a client only when its redirect is that client's own", () => {
    expect(displayName("claude", "Claude", "https://claude.ai/api/mcp/auth_callback")).toBe("Claude");
    expect(displayName("chatgpt", "ChatGPT", "https://chatgpt.com/connector_platform_oauth_redirect")).toBe("ChatGPT");
    expect(displayName("claude", "Claude", "https://claude.ai.evil.example/cb")).toBe("Claude · claude.ai.evil.example");
    expect(displayName("claude", "Claude", "https://evil.example/cb")).toBe("Claude · evil.example");
    expect(displayName(null, "Claude", "https://claude.ai/cb")).toBe("Claude · claude.ai");
    expect(displayName("claude", "Claude Code", "http://localhost:4000/callback")).toBe("Claude Code · a computer");
  });
});
