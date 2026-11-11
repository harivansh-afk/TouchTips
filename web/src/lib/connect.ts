// Everything the site and the app agree on about connecting a client. The app mirrors this in Swift.

export type ClientId = "claude" | "chatgpt" | "claude-code" | "instinct" | "grok" | "other";

export interface ClientGuide {
  id: ClientId;
  name: string;
  /** Steps after the URL is on the clipboard. One action each. */
  steps: string[];
  /** Where "Open" goes: the place in that client where the URL is pasted. */
  open?: string;
}

export const CLIENTS: ClientGuide[] = [
  { id: "claude", name: "Claude", steps: ["Settings → Connectors → Add custom connector", "Paste the URL. Add."], open: "https://claude.ai/settings/connectors" },
  { id: "chatgpt", name: "ChatGPT", steps: ["Settings → Apps & Connectors → Developer mode", "Create → paste the URL, no authentication."], open: "https://chatgpt.com/#settings/Connectors" },
  { id: "claude-code", name: "Claude Code", steps: ["Paste the command in a terminal."] },
  { id: "instinct", name: "Instinct", steps: ["Connections → add an MCP server", "Paste the URL."], open: "https://app.instinct.com" },
  { id: "grok", name: "Grok", steps: ["Settings → Connectors", "Paste the URL."], open: "https://grok.com" },
  { id: "other", name: "Any agent", steps: ["Give it the URL as an MCP server, no auth."] },
];

export function guide(id: string): ClientGuide | undefined {
  return CLIENTS.find((c) => c.id === id);
}
