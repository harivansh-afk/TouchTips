// Everything the site and the app agree on about connecting a client. The app mirrors this in Swift.

export type ClientId = "claude" | "chatgpt" | "grok" | "instinct" | "other";

export interface ClientGuide {
  id: ClientId;
  name: string;
  /** After the URL is on the clipboard. One action each. */
  steps: string[];
  /** Where "Open" goes: the place in that client where the URL is pasted. */
  open?: string;
}

export const CLIENTS: ClientGuide[] = [
  { id: "claude", name: "Claude", steps: ["Settings → Connectors → Add custom connector", "Paste the URL. Add."], open: "https://claude.ai/settings/connectors" },
  { id: "chatgpt", name: "ChatGPT", steps: ["Settings → Apps & Connectors → Developer mode", "Create → paste the URL, no authentication."], open: "https://chatgpt.com/#settings/Connectors" },
  { id: "grok", name: "Grok Bot", steps: ["Tell your Bot: add this MCP server. Paste the URL.", "Or Connect apps → Add a custom connector → Remote HTTPS."] },
  { id: "instinct", name: "Instinct", steps: ["Text Instinct: connect this MCP server. Paste the URL.", "Or Settings → MCP connections → name TouchTips, this URL."], open: "https://app.instinct.com" },
  { id: "other", name: "Any agent", steps: ["Give it the URL as an MCP server, no auth."] },
];

/** For Claude Code, the same URL as a command. */
export function claudeCodeCommand(url: string): string {
  return `claude mcp add --transport http touchtips ${url}`;
}

export function guide(id: string): ClientGuide | undefined {
  return CLIENTS.find((c) => c.id === id);
}
