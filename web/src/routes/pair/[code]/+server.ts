import { messagePage } from "$lib/server/html";
import type { RequestHandler } from "./$types";

/** The universal link. Reached in a browser only when the app isn't installed. */
export const GET: RequestHandler = async () =>
  messagePage("Get TouchTips", "Install TouchTips, then come back to this page and tap the link again.", {
    href: "https://touchtips.app/ios",
    label: "App Store",
  });
