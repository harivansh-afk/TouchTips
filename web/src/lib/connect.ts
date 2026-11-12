// Everything the site and the app agree on about connecting a client. Paths come from docs/connectors.md.

export type ClientId = "claude" | "chatgpt" | "grok" | "instinct" | "other";

export interface ClientGuide {
  id: ClientId;
  name: string;
  /** After the clipboard is filled. One action each. */
  steps: string[];
  /** Where the URL gets pasted, for people reading this on a computer. */
  where?: string;
}

export const CLIENTS: ClientGuide[] = [
  { id: "claude", name: "Claude", steps: ["Check the name and URL, then Continue.", "Sign in now → Add.", "Allow on your iPhone, tapping the number the sign-in page shows."], where: "claude.ai → Customize → Connectors → Add custom connector" },
  { id: "chatgpt", name: "ChatGPT", steps: ["+ → Add custom MCP server → paste the URL.", "OAuth → Create.", "Allow on your iPhone, tapping the number the sign-in page shows."], where: "chatgpt.com/plugins, on the web (the phone app can't add servers)" },
  { id: "grok", name: "Grok Bot", steps: ["In any chat with your Bot, paste the message.", "Sign in when it asks, then Allow on your iPhone, tapping the number the sign-in page shows."], where: "Or on desktop: Connect apps → Add a custom connector → Remote HTTPS" },
  { id: "instinct", name: "Instinct", steps: ["Settings → MCP connections → name TouchTips, this URL.", "Not there? Instinct hasn't opened custom MCP to everyone yet."], where: "app.instinct.com → Settings" },
  { id: "other", name: "Any agent", steps: ["Give it the URL as an MCP server, no auth."] },
];

/** For Claude Code, the same URL as a command. */
export function claudeCodeCommand(url: string): string {
  return `claude mcp add --transport http touchtips --scope user ${url}`;
}

export function guide(id: string): ClientGuide | undefined {
  return CLIENTS.find((c) => c.id === id);
}
