// The three read-only tools AI clients get.
import { McpServer, createMcpHandler } from "@modelcontextprotocol/server";
import { z } from "zod";
import { BASE_URL } from "./config";
import { Index, type MeetingView } from "./snapshot";
import { readSnapshot } from "./store";

const INSTRUCTIONS = `TouchTips is the user's own record of when and where they met each contact.
Every date has a precision. Quote the "when" field exactly as given (for example "March 2024"); never add a day or time the record doesn't have.
"confidence" is "confirmed" when the user checked the record and "estimated" when TouchTips inferred it. Say so when it is estimated.
Link people with their "url". If no one matches, say that rather than guessing.`;

const Meeting = z.object({
  when: z.string(),
  precision: z.enum(["exact", "day", "month", "year"]),
  start: z.string(),
  end: z.string(),
  confidence: z.enum(["confirmed", "estimated"]),
  basis: z.string(),
  place: z.object({ name: z.string().nullable(), latitude: z.number(), longitude: z.number() }).nullable(),
});

const PersonOut = z.object({
  id: z.string(),
  name: z.string(),
  note: z.string().nullable(),
  url: z.string(),
  meetings: z.array(Meeting),
});

function describeMeeting(m: MeetingView): string {
  const where = m.place?.name ? ` at ${m.place.name}` : "";
  const est = m.confidence === "estimated" ? " (estimated)" : "";
  return `${m.when}${where}${est}`;
}

const NO_DATA = {
  isError: true,
  content: [{ type: "text" as const, text: "TouchTips has not synced any data for this account yet. Open TouchTips on the iPhone to sync." }],
};

export function createServer(userHash: string) {
  const server = new McpServer({ name: "TouchTips", version: "1.0.0" }, { instructions: INSTRUCTIONS });
  const loadIndex = async () => {
    const snapshot = await readSnapshot(userHash);
    return snapshot ? new Index(snapshot, BASE_URL) : null;
  };

  server.registerTool(
    "search_people",
    {
      title: "Search people",
      description: "Find contacts by name (or words from the user's note about them) and see when and where the user met each one.",
      inputSchema: z.object({
        query: z.string().min(1).describe("Part of a name, e.g. 'sam' or 'sam climbing'"),
        limit: z.number().int().min(1).max(50).default(10),
      }),
      outputSchema: z.object({ people: z.array(PersonOut) }),
      annotations: { readOnlyHint: true },
    },
    async ({ query, limit }) => {
      const index = await loadIndex();
      if (!index) return NO_DATA;
      const people = index.search(query, limit);
      const text = people.length
        ? people.map((p) => `${p.name} — ${p.meetings.map(describeMeeting).join("; ") || "no meeting recorded"} — ${p.url}`).join("\n")
        : `No one in TouchTips matches "${query}".`;
      return { structuredContent: { people }, content: [{ type: "text", text }] };
    },
  );

  server.registerTool(
    "get_person",
    {
      title: "Get person",
      description: "Full detail for one contact by id (from search_people): every recorded meeting, the place, and the user's note.",
      inputSchema: z.object({ id: z.string().min(1) }),
      outputSchema: z.object({ person: PersonOut.nullable() }),
      annotations: { readOnlyHint: true },
    },
    async ({ id }) => {
      const index = await loadIndex();
      if (!index) return NO_DATA;
      const person = index.person(id);
      const text = person
        ? `${person.name}\n${person.meetings.map((m) => `- ${describeMeeting(m)} — ${m.basis}`).join("\n") || "- no meeting recorded"}${person.note ? `\nNote: ${person.note}` : ""}\n${person.url}`
        : "No person with that id.";
      return { structuredContent: { person }, content: [{ type: "text", text }] };
    },
  );

  server.registerTool(
    "list_meetings",
    {
      title: "List meetings",
      description: "Who the user met, newest first. Filter by a date range and/or a place name, e.g. everyone met in Berlin last spring.",
      inputSchema: z.object({
        from: z.iso.datetime({ offset: true }).optional().describe("Earliest meeting start, ISO 8601"),
        to: z.iso.datetime({ offset: true }).optional().describe("Latest meeting start, ISO 8601"),
        place: z.string().optional().describe("Part of a place name"),
        limit: z.number().int().min(1).max(200).default(50),
      }),
      outputSchema: z.object({ meetings: z.array(Meeting.extend({ person: z.object({ id: z.string(), name: z.string(), url: z.string() }) })) }),
      annotations: { readOnlyHint: true },
    },
    async (args) => {
      const index = await loadIndex();
      if (!index) return NO_DATA;
      const meetings = index.meetings(args);
      const text = meetings.length
        ? meetings.map((m) => `${m.person.name} — ${describeMeeting(m)} — ${m.person.url}`).join("\n")
        : "No meetings match.";
      return { structuredContent: { meetings }, content: [{ type: "text", text }] };
    },
  );

  return server;
}

/** One handler per phone, built per request: the SDK handler is stateless. */
export function mcpHandlerFor(userHash: string) {
  return createMcpHandler(() => createServer(userHash));
}
