/** Origin of this deployment: the custom domain in production, the unique URL on previews. */
export const BASE_URL =
  process.env.PUBLIC_BASE_URL ?? (process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : "http://localhost:5173");

export function connectorUrl(key: string): string {
  return `${BASE_URL}/c/${key}/mcp`;
}
