// Everything the site and the app agree on about connecting a client. The app mirrors this in Swift.

export type ClientId = "claude" | "chatgpt" | "claude-code" | "cursor" | "vscode" | "other";

export interface ClientGuide {
  id: ClientId;
  name: string;
  /** One line under the name on the picker. */
  tagline: string;
  /** Steps after the URL is on the clipboard. Keep each to one action. */
  steps: string[];
  /** Whether the client has a real install link we can open. */
  installLink: boolean;
}

export const CLIENTS: ClientGuide[] = [
  {
    id: "claude",
    name: "Claude",
    tagline: "Web, desktop and iPhone",
    steps: ["Settings → Connectors → Add custom connector", "Paste the URL, leave authentication off", "Add. Ask Claude when you met someone."],
    installLink: false,
  },
  {
    id: "chatgpt",
    name: "ChatGPT",
    tagline: "Developer mode",
    steps: ["Settings → Apps & Connectors → Advanced → Developer mode on", "Create → paste the URL, authentication: none", "Enable it in a chat. Ask when you met someone."],
    installLink: false,
  },
  {
    id: "claude-code",
    name: "Claude Code",
    tagline: "One command",
    steps: ["Paste the command in a terminal", "That's it. Ask in any session."],
    installLink: false,
  },
  {
    id: "cursor",
    name: "Cursor",
    tagline: "One click",
    steps: ["Open the install link on the computer running Cursor", "Confirm. Done."],
    installLink: true,
  },
  {
    id: "vscode",
    name: "VS Code",
    tagline: "One click",
    steps: ["Open the install link on the computer running VS Code", "Confirm. Done."],
    installLink: true,
  },
  {
    id: "other",
    name: "Any agent",
    tagline: "Grok, an iMessage bot, your own",
    steps: ["Give the agent the URL as an MCP server, no auth", "Ask it when you met someone."],
    installLink: false,
  },
];

export function guide(id: string): ClientGuide | undefined {
  return CLIENTS.find((c) => c.id === id);
}

export const PLACEHOLDER_URL = "https://touchtips.app/c/…/mcp";

export function claudeCodeCommand(url: string): string {
  return `claude mcp add --transport http touchtips ${url}`;
}

export function cursorInstallLink(url: string): string {
  const config = btoa(JSON.stringify({ url }));
  return `cursor://anysphere.cursor-deeplink/mcp/install?name=touchtips&config=${config}`;
}

export function vscodeInstallLink(url: string): string {
  const config = encodeURIComponent(JSON.stringify({ type: "http", url }));
  return `https://vscode.dev/redirect/mcp/install?name=touchtips&config=${config}`;
}
