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
    public var isSnapshot: Bool

    public init(
        added: [ContactSnapshot] = [],
        updated: [ContactSnapshot] = [],
        deletedIDs: [String] = [],
        token: Data,
        isSnapshot: Bool = false
    ) {
        self.added = added
        self.updated = updated
        self.deletedIDs = deletedIDs
        self.token = token
        self.isSnapshot = isSnapshot
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
    /// Only a successful Contacts read establishes the lower bound. A change callback can have been
    /// queued during suspension, so process launch/resume time is not evidence of contact absence.
    @discardableResult
    public static func apply(
        _ change: ContactChangeSet, now: Date, to database: AppDatabase
    ) throws -> IngestSummary {
        try database.writer.write { db in
            let firstRun = try db.value(for: .contactsHistoryToken) == nil
            let seenStart = try min(db.date(for: .lastTick) ?? now, now)
            var summary = IngestSummary()

            if change.isSnapshot {
                let currentIDs = Set(change.added.map(\.contactID))
                // An in-app Add can commit while the Contacts snapshot is being read.
                for person in try Person.fetchAll(db)
                    where person.createdAt <= now && !currentIDs.contains(person.contactID) {
                    if try person.delete(db) {
                        summary.deleted += 1
                    }
                }
            }

            for snapshot in change.added {
                if var existing = try Person.fetchOne(db, key: snapshot.contactID) {
                    if existing.name != snapshot.name {
                        existing.name = snapshot.name
                        try existing.update(db)
                        summary.updated += 1
                    }
                    continue
                }
                try Person(contactID: snapshot.contactID, name: snapshot.name, beforeInstall: firstRun, createdAt: now)
                    .insert(db)
                if firstRun {
                    summary.snapshotted += 1
                } else {
                    try Meet(
                        contactID: snapshot.contactID, start: seenStart, end: now,
                        precision: .spanning(seenStart, now), placeID: nil, tier: .dateOnly, userSet: false,
                        addSeenStart: seenStart, addSeenEnd: now, computedAt: now
                    ).insert(db)
                    try PendingNotice(contactID: snapshot.contactID, createdAt: now).insert(db)
                    summary.newPeople += 1
                    summary.added.append(snapshot.contactID)
                }
            }

            for snapshot in change.updated {
                summary.updated += try Person.filter(key: snapshot.contactID)
                    .updateAll(db, Person.Columns.name.set(to: snapshot.name))
            }

            for contactID in change.deletedIDs {
                if try Person.deleteOne(db, key: contactID) {
                    summary.deleted += 1
                }
            }

            try db.setValue(change.token, for: .contactsHistoryToken)
            try db.setDate(now, for: .lastTick)
            return summary
        }
    }

    /// The user's answer. Outranks everything and is never recomputed.
    public static func setUserMeet(
        contactID: String, start: Date, end: Date, precision: Precision, placeID: Int64?, now: Date,
        to database: AppDatabase
    ) throws {
        try database.writer.write { db in
            let existing = try Meet.fetchOne(db, key: contactID)
            try Meet(
                contactID: contactID, start: start, end: end, precision: precision, placeID: placeID, tier: .exact,
                userSet: true, addSeenStart: existing?.addSeenStart, addSeenEnd: existing?.addSeenEnd, computedAt: now
            ).save(db)
        }
    }

    /// Editing a date does not accept the suggested place. A new date-only record has no
    /// outstanding place suggestion; the user can still explicitly record a place later.
    public static func setUserMeetDate(
        contactID: String, start: Date, end: Date, precision: Precision, now: Date,
        to database: AppDatabase
    ) throws {
        try database.writer.write { db in
            if var meet = try Meet.fetchOne(db, key: contactID) {
                meet.start = start
                meet.end = end
                meet.precision = precision
                meet.dateConfirmed = true
                meet.userSet = true
                meet.computedAt = now
                try meet.update(db)
            } else {
                try Meet(
                    contactID: contactID, start: start, end: end, precision: precision,
                    placeID: nil, tier: .exact, userSet: true,
                    addSeenStart: nil, addSeenEnd: nil, computedAt: now
                ).insert(db)
            }
        }
    }

    /// Correct the place without changing how precisely the meeting date is known.
    /// A place alone cannot create a meeting: the user must supply a date first.
    public static func setUserMeetPlace(
        contactID: String, placeID: Int64?, now: Date, to database: AppDatabase
    ) throws {
        try database.writer.write { db in
            guard var meet = try Meet.fetchOne(db, key: contactID), meet.placeID != placeID else { return }
            meet.placeID = placeID
            meet.userSet = true
            meet.placeConfirmed = true
            meet.computedAt = now
            try meet.update(db)
        }
    }

    /// The user agrees with the inferred answer. It becomes theirs, as it stands.
    public static func confirmMeet(contactID: String, now: Date, to database: AppDatabase) throws {
        try database.writer.write { db in
            guard var meet = try Meet.fetchOne(db, key: contactID) else { return }
            meet.userSet = true
            meet.tier = .exact
            meet.dateConfirmed = true
            meet.placeConfirmed = true
            meet.computedAt = now
            try meet.update(db)
        }
    }

    /// The user says they do not know. Removes the answer; a later tick will not recreate it.
    public static func clearMeet(contactID: String, to database: AppDatabase) throws {
        try database.writer.write { db in
            _ = try Meet.deleteOne(db, key: contactID)
            _ = try PendingNotice.deleteOne(db, key: contactID)
        }
    }

    /// Forget our meeting and note while retaining the contact identity. Keeping the person means
    /// later Contacts additions/history resets cannot silently recreate the forgotten meeting.
    public static func forgetPerson(contactID: String, to database: AppDatabase) throws {
        try database.writer.write { db in
            _ = try Meet.deleteOne(db, key: contactID)
            _ = try PendingNotice.deleteOne(db, key: contactID)
            _ = try Person.filter(key: contactID).updateAll(db, Person.Columns.note.set(to: nil))
        }
    }

    /// The user's note about a person. Whitespace-only clears it.
    public static func setNote(contactID: String, note: String, to database: AppDatabase) throws {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try database.writer.write { db in
            _ = try Person.filter(key: contactID).updateAll(
                db,
                Person.Columns.note.set(to: trimmed.isEmpty ? nil : trimmed)
            )
        }
    }

    /// A contact created from inside the app: exact time, chosen place.
    public static func addExact(
        contactID: String,
        name: String,
        at now: Date,
        placeID: Int64?,
        to database: AppDatabase
    ) throws {
        try database.writer.write { db in
            try addExact(contactID: contactID, name: name, at: now, placeID: placeID, in: db)
        }
    }

    /// The selected place, exact meeting, and outbox are one local transaction.
    public static func addExact(
        contactID: String, name: String, at now: Date, place: Place?, to database: AppDatabase
    ) throws {
        try database.writer.write { db in
            let placeID = try place.map {
                try Place.findOrCreate(db, key: $0.key, latitude: $0.latitude, longitude: $0.longitude, name: $0.name)
                    .id!
            }
            try addExact(contactID: contactID, name: name, at: now, placeID: placeID, in: db)
        }
    }

    private static func addExact(
        contactID: String, name: String, at now: Date, placeID: Int64?, in db: Database
    ) throws {
        let existing = try Person.fetchOne(db, key: contactID)
        var person = existing ?? Person(contactID: contactID, name: name, beforeInstall: false, createdAt: now)
        person.name = name
        person.beforeInstall = false
        try person.save(db)
        try Meet(
            contactID: contactID, start: now, end: now, precision: .exact, placeID: placeID, tier: .exact,
            userSet: true, addSeenStart: now, addSeenEnd: now, computedAt: now
        ).save(db)
        if existing == nil || existing?.beforeInstall == true {
            try PendingNotice(contactID: contactID, createdAt: now).insert(db)
        }
    }

    public static func deleteAll(_ database: AppDatabase) throws {
        try database.writer.write { db in
            _ = try Meet.deleteAll(db)
            _ = try Place.deleteAll(db)
            _ = try Person.deleteAll(db)
            _ = try KeyValue.deleteAll(db)
            // Written by earlier builds that captured location. Nothing reads them now.
            try db.execute(sql: "DELETE FROM visit; DELETE FROM heartbeat")
        }
    }
}
