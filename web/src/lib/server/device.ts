// /v1 routes are the phone's. Each one needs the device key.
import type { RequestHandler } from "@sveltejs/kit";
import { deviceFromRequest, type Device } from "./identity";
import { json } from "./json";

export function withDevice(handler: (device: Device, event: Parameters<RequestHandler>[0]) => Promise<Response>): RequestHandler {
  return async (event) => {
    const device = deviceFromRequest(event.request);
    if (!device) return json({ error: "device key required" }, 401);
    return handler(device, event);
  };
}
