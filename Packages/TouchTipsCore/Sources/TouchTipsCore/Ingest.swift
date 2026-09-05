// Every write path into the database. The app hands in plain values; nothing here imports Apple frameworks.

import Foundation
import GRDB

public struct ContactSnapshot: Hashable, Sendable {
    public var contactID: String
    public var name: String

    public init(contactID: String, name: String) {
        self.contactID = contactID
        self.name = name
    }
}

/// What `CNChangeHistoryFetchRequest` reported since the last token.
public struct ContactChangeSet: Sendable {
    public var added: [ContactSnapshot]
    public var updated: [ContactSnapshot]
    public var deletedIDs: [String]
    public var token: Data

    public init(added: [ContactSnapshot] = [], updated: [ContactSnapshot] = [], deletedIDs: [String] = [], token: Data) {
        self.added = added
        self.updated = updated
        self.deletedIDs = deletedIDs
        self.token = token
    }
}

/// A `CLVisit`, flattened.
public struct LiveVisit: Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var accuracyMeters: Double
    public var arrival: Date
    /// nil while the visit is ongoing.
    public var departure: Date?

    public init(latitude: Double, longitude: Double, accuracyMeters: Double, arrival: Date, departure: Date?) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.arrival = arrival
        self.departure = departure
    }
}

/// A precise one-shot location, flattened.
public struct LiveFix: Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var accuracyMeters: Double
    public var at: Date

    public init(latitude: Double, longitude: Double, accuracyMeters: Double, at: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.at = at
    }
}

public struct IngestSummary: Hashable, Sendable {
    public var newPeople = 0
    public var snapshotted = 0
    public var updated = 0
    public var deleted = 0
    /// Contact IDs of the new people, in the order they were seen. What the notification is about.
    public var added: [String] = []

    public init() {}
}

public enum Ingest {
    /// Apply a contacts diff. The first run (no stored token) snapshots everyone as before-install;
    /// later runs treat unknown adds as new people who appeared since the last tick.
    ///
    /// `aliveSince` is when the process was last known to be continuously running. Pass it only when the
    /// diff was prompted by a live change notification: a running process hears an add at once, so the add
    /// cannot predate the moment the process came alive.
    @discardableResult
    public static func apply(
        _ change: ContactChangeSet, now: Date, aliveSince: Date? = nil, to database: AppDatabase
    ) throws -> IngestSummary {
        try database.writer.write { db in
            let firstRun = try db.value(for: .contactsHistoryToken) == nil
            var seenStart = try db.date(for: .lastTick) ?? now
            if let aliveSince { seenStart = min(max(seenStart, aliveSince), now) }
            var summary = IngestSummary()

            for snapshot in change.added {
                guard try Person.filter(key: snapshot.contactID).isEmpty(db) else { continue }
                try Person(contactID: snapshot.contactID, name: snapshot.name, beforeInstall: firstRun, createdAt: now).insert(db)
                if firstRun {
                    summary.snapshotted += 1
                } else {
                    let add = ContactAdd(contactID: snapshot.contactID, seenStart: seenStart, seenEnd: now)
                    try resolve(add, in: db, now: now).insert(db)
                    summary.newPeople += 1
                    summary.added.append(snapshot.contactID)
                }
            }

            for snapshot in change.updated {
                summary.updated += try Person.filter(key: snapshot.contactID)
                    .updateAll(db, Person.Columns.name.set(to: snapshot.name))
            }

            for contactID in change.deletedIDs {
                if try Person.deleteOne(db, key: contactID) { summary.deleted += 1 }
            }

            try db.setValue(change.token, for: .contactsHistoryToken)
            try db.setDate(now, for: .lastTick)
            return summary
        }
    }

    /// Store or extend a visit, then re-resolve any inferred meeting it could improve.
    @discardableResult
    public static func recordLiveVisit(_ live: LiveVisit, now: Date, to database: AppDatabase) throws -> Visit {
        try database.writer.write { db in
            let place = try Place.findOrCreate(
                db, key: PlaceKey.cell(latitude: live.latitude, longitude: live.longitude),
                latitude: live.latitude, longitude: live.longitude
            )
            let placeID = place.id!
            // CoreLocation reports distantPast when the arrival predates monitoring. Use what we have.
            let start = live.arrival == .distantPast ? (live.departure ?? now) : live.arrival
            let end = live.departure ?? .distantFuture

            var visit: Visit
            if var existing = try Visit
                .filter(Visit.Columns.placeID == placeID && Visit.Columns.start == start && Visit.Columns.source == VisitSource.live)
                .fetchOne(db)
            {
                existing.end = end
                existing.accuracyMeters = live.accuracyMeters
                try existing.update(db)
                visit = existing
            } else {
                visit = Visit(placeID: placeID, start: start, end: end, source: .live, accuracyMeters: live.accuracyMeters)
                try visit.insert(db)
            }

            try reresolve(around: start, end, in: db, now: now)
            return visit
        }
    }

    /// Store a fix as a zero-length visit. Any add whose interval contains the instant is witnessed by it.
    @discardableResult
    public static func recordFix(_ fix: LiveFix, now: Date, to database: AppDatabase) throws -> Visit {
        try database.writer.write { db in
            let place = try Place.findOrCreate(
                db, key: PlaceKey.cell(latitude: fix.latitude, longitude: fix.longitude),
                latitude: fix.latitude, longitude: fix.longitude
            )
            var visit = Visit(placeID: place.id!, start: fix.at, end: fix.at, source: .fix, accuracyMeters: fix.accuracyMeters)
            try visit.save(db)
            try reresolve(around: fix.at, fix.at, in: db, now: now)
            return visit
        }
    }

    /// One proof of life. Cheap; the app writes one on every wake and every few minutes while resident.
    @discardableResult
    public static func recordHeartbeat(_ source: WakeSource, at: Date, batteryLevel: Double?, to database: AppDatabase) throws -> Heartbeat {
        try database.writer.write { db in
            var beat = Heartbeat(source: source, at: at, batteryLevel: batteryLevel)
            try beat.insert(db)
            return beat
        }
    }

    /// Recompute every inferred meeting. Used after a history import.
    public static func reresolveAll(now: Date, to database: AppDatabase) throws {
        try database.writer.write { db in
            let meets = try Meet.filter(Meet.Columns.userSet == false).fetchAll(db)
            try reresolve(meets, in: db, now: now)
        }
    }

    /// The user's answer. Outranks everything and is never recomputed.
    public static func setUserMeet(
        contactID: String, start: Date, end: Date, precision: Precision, placeID: Int64?, now: Date, to database: AppDatabase
    ) throws {
        try database.writer.write { db in
            let existing = try Meet.fetchOne(db, key: contactID)
            try Meet(
                contactID: contactID, start: start, end: end, precision: precision, placeID: placeID, tier: .exact,
                userSet: true, addSeenStart: existing?.addSeenStart, addSeenEnd: existing?.addSeenEnd, computedAt: now
            ).save(db)
        }
    }

    /// The user agrees with the inferred answer. It becomes theirs, as it stands.
    public static func confirmMeet(contactID: String, now: Date, to database: AppDatabase) throws {
        try database.writer.write { db in
            guard var meet = try Meet.fetchOne(db, key: contactID) else { return }
            meet.userSet = true
            meet.tier = .exact
            meet.computedAt = now
            try meet.update(db)
        }
    }

    /// The user says they do not know. Removes the answer; a later tick will not recreate it.
    public static func clearMeet(contactID: String, to database: AppDatabase) throws {
        _ = try database.writer.write { db in try Meet.deleteOne(db, key: contactID) }
    }

    /// The user's note about a person. Whitespace-only clears it.
    public static func setNote(contactID: String, note: String, to database: AppDatabase) throws {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try database.writer.write { db in
            _ = try Person.filter(key: contactID).updateAll(db, Person.Columns.note.set(to: trimmed.isEmpty ? nil : trimmed))
        }
    }

    /// A contact created from inside the app: exact time, chosen place.
    public static func addExact(contactID: String, name: String, at now: Date, placeID: Int64?, to database: AppDatabase) throws {
        try database.writer.write { db in
            try Person(contactID: contactID, name: name, beforeInstall: false, createdAt: now).save(db)
            try Meet(
                contactID: contactID, start: now, end: now, precision: .exact, placeID: placeID, tier: .exact,
                userSet: true, addSeenStart: now, addSeenEnd: now, computedAt: now
            ).save(db)
        }
    }

    public static func deleteAll(_ database: AppDatabase) throws {
        try database.writer.write { db in
            _ = try Meet.deleteAll(db)
            _ = try Visit.deleteAll(db)
            _ = try Place.deleteAll(db)
            _ = try Person.deleteAll(db)
            _ = try Heartbeat.deleteAll(db)
            _ = try KeyValue.deleteAll(db)
        }
    }

    // MARK: - Internals

    private static func resolve(_ add: ContactAdd, in db: Database, now: Date) throws -> Meet {
        let visits = try Visit.overlapping(
            add.seenStart.addingTimeInterval(-Resolver.window),
            add.seenEnd.addingTimeInterval(Resolver.window)
        ).fetchAll(db)
        return Resolver.meet(for: add, visits: visits, now: now)
    }

    private static func reresolve(around start: Date, _ end: Date, in db: Database, now: Date) throws {
        let meets = try Meet
            .filter(Meet.Columns.userSet == false)
            .filter(Meet.Columns.addSeenEnd >= start.addingTimeInterval(-Resolver.window))
            .filter(Meet.Columns.addSeenStart <= end.addingTimeInterval(Resolver.window))
            .fetchAll(db)
        try reresolve(meets, in: db, now: now)
    }

    private static func reresolve(_ meets: [Meet], in db: Database, now: Date) throws {
        for meet in meets {
            guard let seenStart = meet.addSeenStart, let seenEnd = meet.addSeenEnd else { continue }
            let add = ContactAdd(contactID: meet.contactID, seenStart: seenStart, seenEnd: seenEnd)
            let fresh = try resolve(add, in: db, now: now)
            if fresh.tier != meet.tier || fresh.placeID != meet.placeID || fresh.start != meet.start || fresh.end != meet.end {
                try fresh.update(db)
            }
        }
    }
}
