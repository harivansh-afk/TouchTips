// Guard for /v1/* routes: the phone must present its device key.
import { json } from "./json";
import { userHashFromRequest } from "./identity";

export function withDevice(handler: (userHash: string) => Promise<Response>) {
  return async ({ request }: { request: Request }) => {
    const userHash = userHashFromRequest(request);
    if (!userHash) return json({ error: "device key required" }, 401);
    return handler(userHash);
  };
}
