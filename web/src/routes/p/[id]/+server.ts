import { messagePage } from "$lib/server/html";
import type { RequestHandler } from "./$types";

/** A person link opened outside the app. */
export const GET: RequestHandler = async () =>
  messagePage("Open in TouchTips", "This link opens a person in TouchTips on your iPhone.", {
    href: "https://touchtips.app/ios",
    label: "Get TouchTips",
  });
