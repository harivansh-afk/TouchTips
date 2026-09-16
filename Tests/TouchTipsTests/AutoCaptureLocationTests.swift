import CoreLocation
@testable import TouchTips
import TouchTipsCore
import XCTest

@MainActor
final class AutoCaptureLocationTests: XCTestCase {
    func testLegacyEnabledPreferenceAndWitnessNeverRequestFix() async throws {
        let name = "AutoCaptureLocationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let db = try AppDatabase.inMemory()
        try Ingest.apply(ContactChangeSet(token: Data([1])), now: .now, to: db)
        defaults.set(true, forKey: CaptureCoordinator.autoCaptureLocationKey)
        defaults.set(PresencePolicy.always.rawValue, forKey: PresencePolicy.key)
        var fixes = 0
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .denied }, submittedIDs: { [] }, submit: { _ in }
        ))
        let capture = CaptureCoordinator(
            database: db, notifier: notifier,
            contacts: CaptureContacts(authorized: { true }, changes: { _ in
                ContactChangeSet(added: [.init(contactID: "new", name: "New")], token: Data([2]))
            }),
            location: CaptureLocation(authorized: { true }, fix: { _ in
                fixes += 1
                return CLLocation(latitude: 37, longitude: -122)
            }),
            defaults: defaults
        )
        await capture.tick(.contacts)
        XCTAssertFalse(capture.autoCaptureLocation)
        XCTAssertEqual(capture.presencePolicy, .off)
        capture.autoCaptureLocation = false
        capture.autoCaptureLocation = true
        capture.presencePolicy = .always
        let witnessed = await capture.witness()
        XCTAssertFalse(witnessed)
        XCTAssertFalse(capture.autoCaptureLocation)
        XCTAssertEqual(capture.presencePolicy, .off)
        XCTAssertEqual(fixes, 0)
        let visits = try await db.reader.read { try Visit.fetchCount($0) }
        XCTAssertEqual(visits, 0)
    }

    func testOffPersistsAndStillDiscoversContactsWithoutLocation()
        async throws {
        let name = "AutoCaptureLocationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let db = try AppDatabase.inMemory()
        try Ingest.apply(ContactChangeSet(token: Data([1])), now: .now, to: db)
        var fixes = 0
        var nextContact = 0
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .denied }, submittedIDs: { [] }, submit: { _ in }
        ))
        func makeCapture() -> CaptureCoordinator {
            CaptureCoordinator(
                database: db, notifier: notifier,
                contacts: CaptureContacts(authorized: { true }, changes: { _ in
                    nextContact += 1
                    return ContactChangeSet(
                        added: [.init(contactID: "\(nextContact)", name: "New person")], token: Data([2])
                    )
                }),
                location: CaptureLocation(authorized: { true }, fix: { _ in
                    fixes += 1
                    return nil
                }),
                defaults: defaults
            )
        }
        let capture = makeCapture()
        XCTAssertFalse(capture.autoCaptureLocation)
        capture.autoCaptureLocation = false
        let relaunched = makeCapture()
        XCTAssertFalse(relaunched.autoCaptureLocation)
        let success = await relaunched.tick(.contacts)
        XCTAssertTrue(success)
        let people = try await db.reader.read { try Person.fetchCount($0) }
        XCTAssertEqual(people, 1)
        XCTAssertEqual(fixes, 0)
        relaunched.record(LiveVisit(
            latitude: 37, longitude: -122, accuracyMeters: 10,
            arrival: .now, departure: nil
        ))
        XCTAssertNil(relaunched.currentVisit)
        let visits = try await db.reader.read { try Visit.fetchCount($0) }
        XCTAssertEqual(visits, 0)
        relaunched.autoCaptureLocation = true
        XCTAssertFalse(makeCapture().autoCaptureLocation)
    }
}
