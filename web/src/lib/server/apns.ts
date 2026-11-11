// Apple Push Notification service, token-based (a .p8 key). Used for one thing: asking the phone to approve a connection.
import { createPrivateKey, sign } from "node:crypto";
import { connect } from "node:http2";

const TOPIC = process.env.APNS_TOPIC ?? "sh.harivan.touchtips";
export const APPROVAL_CATEGORY = "connect-approval";

let cached: { token: string; at: number } | null = null;

function providerToken(): string | null {
  const { APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID } = process.env;
  if (!APNS_KEY || !APNS_KEY_ID || !APNS_TEAM_ID) return null;
  // Apple accepts a token for an hour and rejects refreshing more than every 20 minutes.
  if (cached && Date.now() - cached.at < 40 * 60 * 1000) return cached.token;
  const header = Buffer.from(JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID })).toString("base64url");
  const iat = Math.floor(Date.now() / 1000);
  const claims = Buffer.from(JSON.stringify({ iss: APNS_TEAM_ID, iat })).toString("base64url");
  const key = createPrivateKey(APNS_KEY.replace(/\\n/g, "\n"));
  const signature = sign("sha256", Buffer.from(`${header}.${claims}`), { key, dsaEncoding: "ieee-p1363" }).toString("base64url");
  cached = { token: `${header}.${claims}.${signature}`, at: Date.now() };
  return cached.token;
}

export type PushResult = "sent" | "unconfigured" | "bad-token" | "failed";

export interface ApprovalPush {
  deviceToken: string;
  env: "sandbox" | "production";
  requestId: string;
  displayName: string;
  expiresInSeconds: number;
}

export async function pushApproval(p: ApprovalPush): Promise<PushResult> {
  let jwt: string | null;
  try {
    jwt = providerToken();
  } catch (e) {
    // A broken key must not break sign-in: the phone can still allow from the app.
    console.error("apns key unusable", e instanceof Error ? e.message : e);
    return "failed";
  }
  if (!jwt) return "unconfigured";
  if (!/^[0-9a-f]{64,200}$/i.test(p.deviceToken)) return "bad-token";
  const payload = JSON.stringify({
    aps: {
      alert: { title: `Allow ${p.displayName}?`, body: `${p.displayName} wants to read your people and meetings. Tap, then pick the number it shows.` },
      sound: "default",
      category: APPROVAL_CATEGORY,
    },
    requestId: p.requestId,
  });
  const host = p.env === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  return new Promise((resolve) => {
    const session = connect(host);
    const done = (result: PushResult) => {
      session.close();
      resolve(result);
    };
    session.on("error", () => done("failed"));
    session.setTimeout(8000, () => done("failed"));
    const req = session.request({
      ":method": "POST",
      ":path": `/3/device/${p.deviceToken}`,
      authorization: `bearer ${jwt}`,
      "apns-topic": TOPIC,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + p.expiresInSeconds),
      "apns-collapse-id": p.requestId.slice(0, 64),
    });
    let status = 0;
    let body = "";
    req.on("response", (headers) => (status = Number(headers[":status"])));
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => {
      if (status === 200) return done("sent");
      console.error(`apns ${status} ${body}`);
      done(status === 410 || /BadDeviceToken|Unregistered|DeviceTokenNotForTopic/.test(body) ? "bad-token" : "failed");
    });
    req.on("error", () => done("failed"));
    req.end(payload);
  });
}
