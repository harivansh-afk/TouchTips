import Contacts
@testable import TouchTips
import TouchTipsCore
import XCTest

@MainActor
final class ContactCreationTests: XCTestCase {
    func testLocalFailureRetriesTheSameSystemContactAndOriginalTime() throws {
        let db = try AppDatabase.inMemory()
        var operations: [Bool] = []
        var identities: [String] = []
        let creation = ContactCreation { contact, updating in
            operations.append(updating)
            identities.append(contact.identifier)
        }
        let start = Date(timeIntervalSince1970: 1000)
        try db.writer.write {
            try $0
                .execute(
                    sql: "CREATE TRIGGER fail_person BEFORE INSERT ON person BEGIN SELECT RAISE(ABORT, 'test'); END"
                )
        }
        XCTAssertThrowsError(try creation.save(name: "First", phone: "", place: nil, at: start, to: db))
        try db.writer.write { try $0.execute(sql: "DROP TRIGGER fail_person") }
        try creation.save(name: "Edited", phone: "", place: nil, at: start.addingTimeInterval(60), to: db)
        XCTAssertEqual(operations, [false, true], "Retry must update the saved contact, never add another")
        XCTAssertEqual(Set(identities).count, 1)
        let row = try XCTUnwrap(db.reader.read { try Person.rows().fetchOne($0) })
        XCTAssertEqual(row.person.name, "Edited")
        XCTAssertEqual(row.meet?.start, start)
        XCTAssertEqual(try db.reader.read { try PendingNotice.fetchCount($0) }, 1)
    }

    func testSystemContactFailureDoesNotCommitAnAppPerson() throws {
        let db = try AppDatabase.inMemory()
        let creation = ContactCreation { _, _ in throw CNError(.communicationError) }
        XCTAssertThrowsError(try creation.save(name: "A", phone: "", place: nil, to: db))
        XCTAssertEqual(try db.reader.read { try Person.fetchCount($0) }, 0)
    }
}
