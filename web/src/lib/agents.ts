// The agents the site shows. Site only: the app knows the clients in connect.ts, and anything without its own
// guide there connects as "other".

import type { ClientId } from "./connect";

export interface Agent {
  name: string;
  /** File in static/agents. SVGs are drawn as a mask in the text color; anything else is shown as is. */
  icon: string;
  client: ClientId;
}

export const AGENTS: Agent[] = [
  { name: "Claude", icon: "claude.svg", client: "claude" },
  { name: "ChatGPT", icon: "openai.svg", client: "chatgpt" },
  { name: "Grok Bot", icon: "grok.svg", client: "other" },
  { name: "Instinct", icon: "instinct.png", client: "other" },
  { name: "OpenClaw", icon: "openclaw.svg", client: "other" },
  { name: "Hermes", icon: "hermesagent.svg", client: "other" },
  { name: "Claude Code", icon: "claudecode.svg", client: "claude-code" },
  { name: "Codex", icon: "codex.svg", client: "other" },
  { name: "Cursor", icon: "cursor.svg", client: "cursor" },
  { name: "Anything else", icon: "plus.svg", client: "other" },
];

export const CLIENT_ICONS: Record<ClientId, string> = {
  claude: "claude.svg",
  chatgpt: "openai.svg",
  "claude-code": "claudecode.svg",
  cursor: "cursor.svg",
  vscode: "vscode.svg",
  other: "plus.svg",
};

export function iconStyle(icon: string): string {
  return `--i:url(/agents/${icon})`;
}

export function iconClass(icon: string): string {
  return icon.endsWith(".svg") ? "ico" : "ico img";
}
