// The agents the site shows. Site only: the app knows the clients in connect.ts, and anything without its own
// guide there connects as "other".

import type { ClientId } from "./connect";

export interface Agent {
  name: string;
  /** File in static/agents, drawn as a mask in the text color. */
  icon: string;
  client: ClientId;
}

export const AGENTS: Agent[] = [
  { name: "Claude", icon: "claude.svg", client: "claude" },
  { name: "ChatGPT", icon: "openai.svg", client: "chatgpt" },
  { name: "Grok Bot", icon: "grokbot.svg", client: "grok" },
  { name: "Instinct", icon: "instinct.png", client: "instinct" },
  { name: "OpenClaw", icon: "openclaw.svg", client: "other" },
  { name: "Hermes", icon: "hermesagent.svg", client: "other" },
  { name: "Codex", icon: "codex.svg", client: "other" },
  { name: "Anything else", icon: "plus.svg", client: "other" },
];

export const CLIENT_ICONS: Record<ClientId, string> = {
  claude: "claude.svg",
  chatgpt: "openai.svg",
  grok: "grokbot.svg",
  instinct: "instinct.png",
  other: "plus.svg",
};

export function iconStyle(icon: string): string {
  return `--i:url(/agents/${icon})`;
}

export function iconClass(_icon: string): string {
  return "ico";
}
