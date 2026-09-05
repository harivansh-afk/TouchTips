// Opens the database and owns the schema. Migrations are additive only; this data exists nowhere else.

import Foundation
@_exported import GRDB

public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter
    public var reader: any DatabaseReader {
        writer
    }

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// `directory/touchtips.sqlite`, created if needed. WAL mode via DatabasePool.
    public static func onDisk(in directory: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("touchtips.sqlite")
        return try AppDatabase(DatabasePool(path: url.path, configuration: configuration))
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: configuration))
    }

    private static var configuration: Configuration {
        var config = Configuration()
        #if DEBUG
            config.publicStatementArguments = true
        #endif
        return config
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "person") { t in
                t.primaryKey("contactID", .text)
                t.column("name", .text).notNull()
                t.column("beforeInstall", .boolean).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "place") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("key", .text).notNull().unique()
                t.column("latitude", .double).notNull()
                t.column("longitude", .double).notNull()
                t.column("name", .text)
                t.column("namedAt", .datetime)
            }
            try db.create(indexOn: "place", columns: ["latitude"])
            try db.create(indexOn: "place", columns: ["longitude"])

            try db.create(table: "visit") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("placeID", .integer).notNull().references("place", onDelete: .cascade)
                t.column("start", .datetime).notNull()
                t.column("end", .datetime).notNull()
                t.column("source", .text).notNull()
                t.column("accuracyMeters", .double)
                t.uniqueKey(["placeID", "start", "source"])
            }
            try db.create(indexOn: "visit", columns: ["start"])
            try db.create(indexOn: "visit", columns: ["end"])

            try db.create(table: "meet") { t in
                t.primaryKey("contactID", .text).references("person", onDelete: .cascade)
                t.column("start", .datetime).notNull()
                t.column("end", .datetime).notNull()
                t.column("precision", .text).notNull()
                t.column("placeID", .integer).references("place", onDelete: .setNull)
                t.column("tier", .integer).notNull()
                t.column("userSet", .boolean).notNull()
                t.column("addSeenStart", .datetime)
                t.column("addSeenEnd", .datetime)
                t.column("computedAt", .datetime).notNull()
            }
            try db.create(indexOn: "meet", columns: ["placeID"])
            try db.create(indexOn: "meet", columns: ["start"])

            try db.create(table: "kv") { t in
                t.primaryKey("key", .text)
                t.column("value", .blob).notNull()
            }
        }

        migrator.registerMigration("v2") { db in
            try db.create(table: "heartbeat") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("source", .text).notNull()
                t.column("at", .datetime).notNull()
                t.column("batteryLevel", .double)
            }
            try db.create(indexOn: "heartbeat", columns: ["at"])
        }

        migrator.registerMigration("v3") { db in
            try db.alter(table: "person") { t in
                t.add(column: "note", .text)
            }
        }

        migrator.registerMigration("v4-notification-outbox") { db in
            try db.create(table: "pendingNotice") { t in
                t.primaryKey("contactID", .text).references("person", onDelete: .cascade)
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v5-meeting-confirmation") { db in
            try db.alter(table: "meet") { t in
                t.add(column: "dateConfirmed", .boolean).notNull().defaults(to: false)
                t.add(column: "placeConfirmed", .boolean).notNull().defaults(to: false)
            }
            // Legacy edits did not record which fields were confirmed. Preserve their values and
            // edit protection, but only recognize the unambiguous in-app Add signature as confirmed.
            try db.execute(sql: """
            UPDATE meet SET dateConfirmed = 1, placeConfirmed = 1
            WHERE userSet = 1 AND precision = 'exact'
              AND start = end AND start = addSeenStart AND end = addSeenEnd
            """)
            // Repair automatic answers whose interval was previously narrowed to a visit or fix.
            for meet in try Meet.filter(Meet.Columns.userSet == false).fetchAll(db) {
                guard let start = meet.addSeenStart, let end = meet.addSeenEnd else { continue }
                let visits = try Visit.overlapping(
                    start.addingTimeInterval(-Resolver.window), end.addingTimeInterval(Resolver.window)
                ).fetchAll(db)
                let answer = Resolver.meet(
                    for: ContactAdd(contactID: meet.contactID, seenStart: start, seenEnd: end),
                    visits: visits, now: meet.computedAt
                )
                try answer.update(db)
            }
        }

        return migrator
    }
}
