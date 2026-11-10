import { describe, expect, it } from "vitest";
import { Index, SnapshotSchema, formatWhen, normalize } from "../src/snapshot";
import { fixture } from "./fixture";

const index = new Index(fixture, "https://mcp.example");

describe("formatWhen", () => {
  it("rounds to the record's precision in the phone's time zone", () => {
    expect(formatWhen("2024-03-14T19:12:00Z", "exact", "America/New_York")).toBe("March 14, 2024 at 3:12 PM");
    expect(formatWhen("2024-03-14T19:12:00Z", "day", "America/New_York")).toBe("March 14, 2024");
    expect(formatWhen("2025-05-20T00:00:00Z", "month", "America/New_York")).toBe("May 2025");
    expect(formatWhen("2022-11-01T00:00:00Z", "year", "UTC")).toBe("2022");
  });
  it("falls back to UTC for a bad time zone", () => {
    expect(formatWhen("2024-03-14T23:30:00Z", "day", "Mars/Olympus")).toBe("March 14, 2024");
  });
});

describe("search", () => {
  it("matches name prefixes, ignoring case and accents", () => {
    expect(index.search("jose", 10).map((p) => p.name)).toEqual(["José Álvarez"]);
    expect(index.search("SAM", 10).map((p) => p.name)).toEqual(["Sam Okafor", "Samira Haddad"]);
  });
  it("ranks word-start matches above note matches and requires every token", () => {
    expect(index.search("sam climbing", 10).map((p) => p.name)).toEqual(["Sam Okafor"]);
    expect(index.search("sam nowhere", 10)).toEqual([]);
  });
  it("returns meetings with display strings, confidence and links", () => {
    const [sam] = index.search("okafor", 1);
    expect(sam.url).toBe("https://mcp.example/p/p-sam");
    expect(sam.meetings[0]).toMatchObject({
      when: "March 14, 2024 at 3:12 PM",
      confidence: "confirmed",
      basis: "recorded in TouchTips",
      place: { name: "Brooklyn Boulders" },
    });
    expect(normalize("  Éclair  Au  Chocolat ")).toBe("eclair au chocolat");
  });
});

describe("meetings", () => {
  it("lists newest first and filters by range and place", () => {
    expect(index.meetings({ limit: 10 }).map((m) => m.person.name)).toEqual(["Samira Haddad", "Sam Okafor", "José Álvarez"]);
    expect(index.meetings({ from: "2024-01-01T00:00:00Z", to: "2024-12-31T00:00:00Z", limit: 10 }).map((m) => m.person.name)).toEqual(["Sam Okafor"]);
    expect(index.meetings({ place: "boulders", limit: 10 }).map((m) => m.person.name)).toEqual(["Sam Okafor"]);
  });
  it("marks estimates", () => {
    const samira = index.person("p-sami")!;
    expect(samira.meetings[0]).toMatchObject({ when: "May 2025", confidence: "estimated", basis: "estimated from when the contact appeared on the phone", place: null });
  });
});

describe("schema", () => {
  it("accepts the fixture and rejects a bad precision", () => {
    expect(SnapshotSchema.safeParse(fixture).success).toBe(true);
    const bad = { ...fixture, meets: [{ ...fixture.meets[0], precision: "week" }] };
    expect(SnapshotSchema.safeParse(bad).success).toBe(false);
  });
});
