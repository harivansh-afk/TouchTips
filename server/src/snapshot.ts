// The phone's data, as pushed. Mirrors Records.swift in the app, minus anything Contacts owns.
import { z } from "zod";

const Precision = z.enum(["exact", "day", "month", "year"]);
const Tier = z.union([z.literal(0), z.literal(1), z.literal(2), z.literal(3)]);

export const SnapshotSchema = z.object({
  version: z.literal(1),
  generatedAt: z.iso.datetime({ offset: true }),
  timeZone: z.string().min(1),
  people: z.array(
    z.object({
      id: z.string().min(1),
      name: z.string(),
      note: z.string().nullish(),
      createdAt: z.iso.datetime({ offset: true }),
    }),
  ),
  places: z.array(
    z.object({
      id: z.number().int(),
      name: z.string().nullish(),
      latitude: z.number(),
      longitude: z.number(),
    }),
  ),
  meets: z.array(
    z.object({
      personId: z.string().min(1),
      start: z.iso.datetime({ offset: true }),
      end: z.iso.datetime({ offset: true }),
      precision: Precision,
      tier: Tier,
      placeId: z.number().int().nullish(),
      userSet: z.boolean(),
      dateConfirmed: z.boolean(),
      placeConfirmed: z.boolean(),
    }),
  ),
});

export type Snapshot = z.infer<typeof SnapshotSchema>;
export type Meet = Snapshot["meets"][number];
export type Person = Snapshot["people"][number];
export type Place = Snapshot["places"][number];

export interface PlaceView {
  name: string | null;
  latitude: number;
  longitude: number;
}

export interface MeetingView {
  /** Human-readable date at the record's precision. Quote verbatim. */
  when: string;
  precision: Meet["precision"];
  start: string;
  end: string;
  /** Whether the user confirmed the date, or TouchTips estimated it. */
  confidence: "confirmed" | "estimated";
  /** Where the date came from. */
  basis: string;
  place: PlaceView | null;
}

export interface PersonView {
  id: string;
  name: string;
  note: string | null;
  url: string;
  meetings: MeetingView[];
}

export interface MeetingWithPerson extends MeetingView {
  person: { id: string; name: string; url: string };
}

const BASIS: Record<Meet["tier"], string> = {
  0: "recorded in TouchTips",
  1: "estimated from an earlier location visit",
  2: "estimated from an earlier location visit",
  3: "estimated from when the contact appeared on the phone",
};

export function safeTimeZone(tz: string): string {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return tz;
  } catch {
    return "UTC";
  }
}

export function formatWhen(start: string, precision: Meet["precision"], timeZone: string): string {
  const d = new Date(start);
  const tz = safeTimeZone(timeZone);
  switch (precision) {
    case "exact":
      return new Intl.DateTimeFormat("en-US", { timeZone: tz, dateStyle: "long", timeStyle: "short" }).format(d);
    case "day":
      return new Intl.DateTimeFormat("en-US", { timeZone: tz, dateStyle: "long" }).format(d);
    case "month":
      return new Intl.DateTimeFormat("en-US", { timeZone: tz, month: "long", year: "numeric" }).format(d);
    case "year":
      return new Intl.DateTimeFormat("en-US", { timeZone: tz, year: "numeric" }).format(d);
  }
}

/** Lowercase, strip accents, collapse whitespace. */
export function normalize(s: string): string {
  return s
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

export class Index {
  private people = new Map<string, Person>();
  private places = new Map<number, Place>();
  private meetsByPerson = new Map<string, Meet[]>();

  constructor(
    readonly snapshot: Snapshot,
    private readonly publicUrl: string,
  ) {
    for (const p of snapshot.people) this.people.set(p.id, p);
    for (const pl of snapshot.places) this.places.set(pl.id, pl);
    for (const m of snapshot.meets) {
      const list = this.meetsByPerson.get(m.personId) ?? [];
      list.push(m);
      this.meetsByPerson.set(m.personId, list);
    }
    for (const list of this.meetsByPerson.values()) list.sort((a, b) => a.start.localeCompare(b.start));
  }

  personUrl(id: string): string {
    return `${this.publicUrl}/p/${encodeURIComponent(id)}`;
  }

  private placeView(id: number | null | undefined): PlaceView | null {
    if (id == null) return null;
    const pl = this.places.get(id);
    if (!pl) return null;
    return { name: pl.name ?? null, latitude: pl.latitude, longitude: pl.longitude };
  }

  meetingView(m: Meet): MeetingView {
    return {
      when: formatWhen(m.start, m.precision, this.snapshot.timeZone),
      precision: m.precision,
      start: m.start,
      end: m.end,
      confidence: m.dateConfirmed ? "confirmed" : "estimated",
      basis: BASIS[m.tier],
      place: this.placeView(m.placeId),
    };
  }

  personView(p: Person): PersonView {
    return {
      id: p.id,
      name: p.name,
      note: p.note ?? null,
      url: this.personUrl(p.id),
      meetings: (this.meetsByPerson.get(p.id) ?? []).map((m) => this.meetingView(m)),
    };
  }

  person(id: string): PersonView | null {
    const p = this.people.get(id);
    return p ? this.personView(p) : null;
  }

  /** Every query token must prefix-match a word of the name (or the note). Word-start matches rank first. */
  search(query: string, limit: number): PersonView[] {
    const tokens = normalize(query).split(" ").filter(Boolean);
    if (tokens.length === 0) return [];
    const scored: { score: number; p: Person }[] = [];
    for (const p of this.people.values()) {
      const name = normalize(p.name);
      const words = name.split(" ");
      const note = normalize(p.note ?? "");
      let score = 0;
      let ok = true;
      for (const t of tokens) {
        if (words.some((w) => w.startsWith(t))) score += 3;
        else if (name.includes(t)) score += 2;
        else if (note.includes(t)) score += 1;
        else {
          ok = false;
          break;
        }
      }
      if (ok) scored.push({ score, p });
    }
    scored.sort((a, b) => b.score - a.score || a.p.name.localeCompare(b.p.name));
    return scored.slice(0, limit).map(({ p }) => this.personView(p));
  }

  /** Meetings newest first, optionally within [from, to] and at a place whose name contains `place`. */
  meetings(opts: { from?: string; to?: string; place?: string; limit: number }): MeetingWithPerson[] {
    const from = opts.from ? Date.parse(opts.from) : -Infinity;
    const to = opts.to ? Date.parse(opts.to) : Infinity;
    const place = opts.place ? normalize(opts.place) : null;
    const out: MeetingWithPerson[] = [];
    for (const m of this.snapshot.meets) {
      const t = Date.parse(m.start);
      if (t < from || t > to) continue;
      const view = this.meetingView(m);
      if (place && !(view.place?.name && normalize(view.place.name).includes(place))) continue;
      const p = this.people.get(m.personId);
      if (!p) continue;
      out.push({ ...view, person: { id: p.id, name: p.name, url: this.personUrl(p.id) } });
    }
    out.sort((a, b) => b.start.localeCompare(a.start));
    return out.slice(0, opts.limit);
  }
}
