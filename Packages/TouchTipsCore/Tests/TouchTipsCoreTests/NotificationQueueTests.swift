import Foundation
import Testing
@testable import TouchTipsCore

struct NotificationQueueTests {
    @Test func snapshotPreservesAnExactAddCommittedAfterTheReadBegan() throws {
        let db = try AppDatabase.inMemory()
        let readStarted = Date(timeIntervalSince1970: 1000)
        try Ingest.addExact(
            contactID: "during-read",
            name: "New",
            at: readStarted.addingTimeInterval(1),
            placeID: nil,
            to: db
        )
        try Ingest.apply(ContactChangeSet(token: Data([1]), isSnapshot: true), now: readStarted, to: db)
        #expect(try db.reader.read { try Meet.fetchOne($0, key: "during-read")?.userSet } == true)
        #expect(try db.reader.read { try PendingNotice.fetchCount($0) } == 1)
    }

    private func baseline(_ db: AppDatabase) throws {
        try Ingest.apply(ContactChangeSet(token: Data([1])), now: .now, to: db)
    }

    @Test func queueAndTokenCommitTogetherAndReplayDoesNotDuplicate() throws {
        let db = try AppDatabase.inMemory()
        try baseline(db)
        let changes = ContactChangeSet(added: [.init(contactID: "a", name: "Alice")], token: Data([2]))
        try Ingest.apply(changes, now: .now, to: db)
        try Ingest.apply(changes, now: .now, to: db)
        #expect(try db.reader.read { try PendingNotice.fetchCount($0) } == 1)
        #expect(try db.reader.read { try $0.value(for: .contactsHistoryToken) } == Data([2]))
        _ = try db.writer.write { try PendingNotice.deleteOne($0, key: "a") }
        try Ingest.apply(changes, now: .now, to: db)
        #expect(try db.reader.read { try PendingNotice.fetchCount($0) } == 0)
    }

    @Test func failedQueueWriteRollsBackContactAndToken() throws {
        let db = try AppDatabase.inMemory()
        try baseline(db)
        try db.writer.write { db in
            try db
                .execute(
                    sql: "CREATE TRIGGER fail_notice BEFORE INSERT ON pendingNotice BEGIN SELECT RAISE(ABORT, 'test failure'); END"
                )
        }
        #expect(throws: (any Error).self) {
            try Ingest.apply(
                ContactChangeSet(added: [.init(contactID: "a", name: "Alice")], token: Data([2])),
                now: .now,
                to: db
            )
        }
        #expect(try db.reader.read { try Person.fetchCount($0) } == 0)
        #expect(try db.reader.read { try $0.value(for: .contactsHistoryToken) } == Data([1]))
    }

    @Test func queueSurvivesDatabaseReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let db = try AppDatabase.onDisk(in: directory)
            try baseline(db)
            try Ingest.apply(
                ContactChangeSet(added: [.init(contactID: "a", name: "Alice")], token: Data([2])),
                now: .now,
                to: db
            )
        }
        let reopened = try AppDatabase.onDisk(in: directory)
        #expect(try reopened.reader.read { try PendingNotice.all().fetchAll($0).map(\.contactID) } == ["a"])
    }

    @Test func snapshotReconcilesNamesAndDeletionsWithoutLosingUserNotes() throws {
        let db = try AppDatabase.inMemory()
        try baseline(db)
        try Ingest.apply(
            ContactChangeSet(
                added: [.init(contactID: "a", name: "Alice"), .init(contactID: "b", name: "Bob")],
                token: Data([2])
            ),
            now: .now,
            to: db
        )
        try Ingest.setNote(contactID: "a", note: "Keep this", to: db)
        let summary = try Ingest.apply(
            ContactChangeSet(added: [.init(contactID: "a", name: "Alicia")], token: Data([3]), isSnapshot: true),
            now: .now,
            to: db
        )
        #expect(summary.deleted == 1)
        #expect(summary.newPeople == 0)
        let person = try db.reader.read { try Person.fetchOne($0, key: "a") }
        #expect(person?.name == "Alicia")
        #expect(person?.note == "Keep this")
        #expect(try db.reader.read { try PendingNotice.all().fetchAll($0).map(\.contactID) } == ["a"])
    }

    @Test func firstSnapshotIsSilentAndExactAddQueuesOnce() throws {
        let db = try AppDatabase.inMemory()
        try Ingest.apply(
            ContactChangeSet(added: [.init(contactID: "old", name: "Old")], token: Data([1]), isSnapshot: true),
            now: .now,
            to: db
        )
        #expect(try db.reader.read { try PendingNotice.fetchCount($0) } == 0)
        try Ingest.addExact(contactID: "new", name: "New", at: .now, placeID: nil, to: db)
        try Ingest.apply(
            ContactChangeSet(added: [.init(contactID: "new", name: "New")], token: Data([2])),
            now: .now,
            to: db
        )
        #expect(try db.reader.read { try PendingNotice.fetchCount($0) } == 1)
        try Ingest.clearMeet(contactID: "new", to: db)
        #expect(try db.reader.read { try PendingNotice.fetchCount($0) } == 0)
    }
}
