#if DEBUG && targetEnvironment(simulator)
    import Contacts
    import Foundation
    import TouchTipsCore

    /// Explicit simulator-only data sets. Real screens and persistence still run unchanged.
    enum QATestFixture {
        static func database(in support: URL) throws -> AppDatabase? {
            let environment = ProcessInfo.processInfo.environment
            guard let session = environment["TOUCHTIPS_QA_SESSION"],
                  UUID(uuidString: session) != nil else { return nil }
            let database = try AppDatabase.onDisk(in: support.appendingPathComponent("QATests/\(session)"))
            if let token = CNContactStore().currentHistoryToken {
                try Ingest.apply(ContactChangeSet(token: token), now: .now, to: database)
            }
            guard environment["TOUCHTIPS_QA_DATA"] != "empty" else { return database }
            try database.writer.write { db in
                guard try Person.fetchCount(db) == 0 else { return }
                let now = Date.now
                var cafe = Place(
                    key: "qa-cafe",
                    latitude: 38.0293,
                    longitude: -78.4767,
                    name: "QA Coffee",
                    namedAt: now
                )
                var park = Place(key: "qa-park", latitude: 38.0405, longitude: -78.5020, name: "QA Park", namedAt: now)
                try cafe.insert(db)
                try park.insert(db)
                let count = environment["TOUCHTIPS_QA_DATA"] == "large" ? 1000 : 30
                for index in 0 ..< count {
                    let id = "qa-person-\(index)"
                    let start = now.addingTimeInterval(-Double(index + 1) * 86400)
                    let name = index == 0 ? "QA Alice" : index == 1 ? "QA Bob" : "QA Person \(String(format: "%04d", index))"
                    try Person(contactID: id, name: name, beforeInstall: false, createdAt: start).insert(db)
                    try Meet(
                        contactID: id, start: start, end: start, precision: .exact,
                        placeID: index == 0 ? cafe.id : park.id, tier: .exact, userSet: true,
                        addSeenStart: start, addSeenEnd: start, computedAt: now
                    ).insert(db)
                }
                try Person(contactID: "qa-undocumented", name: "QA Undocumented", beforeInstall: true, createdAt: now)
                    .insert(db)
            }
            return database
        }
    }
#endif
