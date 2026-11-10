import type { Snapshot } from "../src/snapshot";

export const fixture: Snapshot = {
  version: 1,
  generatedAt: "2026-11-10T20:00:00Z",
  timeZone: "America/New_York",
  people: [
    { id: "p-sam", name: "Sam Okafor", note: "climbing gym, lends chalk", createdAt: "2024-03-14T19:12:00Z" },
    { id: "p-sami", name: "Samira Haddad", note: null, createdAt: "2025-06-02T10:00:00Z" },
    { id: "p-jose", name: "José Álvarez", note: null, createdAt: "2023-01-01T00:00:00Z" },
  ],
  places: [
    { id: 1, name: "Brooklyn Boulders", latitude: 40.68, longitude: -73.98 },
    { id: 2, name: null, latitude: 52.52, longitude: 13.4 },
  ],
  meets: [
    { personId: "p-sam", start: "2024-03-14T19:12:00Z", end: "2024-03-14T19:12:00Z", precision: "exact", tier: 0, placeId: 1, userSet: true, dateConfirmed: true, placeConfirmed: true },
    { personId: "p-sami", start: "2025-05-20T00:00:00Z", end: "2025-06-30T00:00:00Z", precision: "month", tier: 3, placeId: null, userSet: false, dateConfirmed: false, placeConfirmed: false },
    { personId: "p-jose", start: "2022-11-01T00:00:00Z", end: "2023-02-01T00:00:00Z", precision: "year", tier: 3, placeId: 2, userSet: false, dateConfirmed: false, placeConfirmed: false },
  ],
};
