// Opens the database and owns the schema. Migrations are additive only; this data exists nowhere else.

import Foundation
@_exported import GRDB

public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter
    public var reader: any DatabaseReader { writer }

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

    private static var migrator: DatabaseMigrator {
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

        return migrator
    }
}
