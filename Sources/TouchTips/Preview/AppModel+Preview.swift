import Foundation
import TouchTipsCore

extension AppModel {
    /// An in-memory app with a handful of people across two months, for previews only.
    /// `start()` is never called, so nothing touches Contacts or CoreLocation.
    static let preview: AppModel = {
        // Preview data: a failure here is a programming error worth a crash in Xcode.
        let database = try! AppDatabase.inMemory()
        try! seed(database)
        return AppModel(database: database)
    }()

    private static func seed(_ database: AppDatabase) throws {
        let calendar = Calendar.current
        let now = Date()
        func daysAgo(_ days: Int, hour: Int, minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -days, to: now)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        try database.writer.write { db in
            var cafe = Place(
                key: PlaceKey.cell(latitude: 38.0293, longitude: -78.4767),
                latitude: 38.0293, longitude: -78.4767, name: "Grit Coffee, Charlottesville", namedAt: now
            )
            try cafe.insert(db)
            var rotunda = Place(
                key: PlaceKey.cell(latitude: 38.0356, longitude: -78.5034),
                latitude: 38.0356, longitude: -78.5034, name: "Rotunda, UVA", namedAt: now
            )
            try rotunda.insert(db)
            var unnamed = Place(key: PlaceKey.cell(latitude: 37.7763, longitude: -122.4241), latitude: 37.7763, longitude: -122.4241)
            try unnamed.insert(db)

            let visits: [(Place, Int, Int, Int)] = [
                (cafe, 2, 10, 12), (rotunda, 9, 15, 17), (cafe, 25, 8, 9), (unnamed, 41, 18, 21),
            ]
            for (place, days, from, to) in visits {
                var visit = Visit(placeID: place.id!, start: daysAgo(days, hour: from), end: daysAgo(days, hour: to), source: .live)
                try visit.insert(db)
            }

            struct Seed {
                let id: String
                let name: String
                let place: Place?
                let days: Int
                let hour: Int
                let precision: Precision
                let tier: Tier
            }
            let people = [
                Seed(id: "maya", name: "Maya Kapoor", place: cafe, days: 2, hour: 10, precision: .day, tier: .witnessed),
                Seed(id: "jonah", name: "Jonah Okafor", place: rotunda, days: 9, hour: 16, precision: .exact, tier: .exact),
                Seed(id: "tomas", name: "Tomás Leal", place: nil, days: 20, hour: 12, precision: .day, tier: .dateOnly),
                Seed(id: "dev", name: "Dev Patel", place: cafe, days: 25, hour: 8, precision: .day, tier: .witnessed),
                Seed(id: "lena", name: "Lena Novak", place: unnamed, days: 41, hour: 19, precision: .month, tier: .inferred),
            ]
            for seed in people {
                let start = daysAgo(seed.days, hour: seed.hour, minute: 41)
                try Person(contactID: seed.id, name: seed.name, beforeInstall: false, createdAt: start).save(db)
                try Meet(
                    contactID: seed.id, start: start, end: start.addingTimeInterval(21 * 60), precision: seed.precision,
                    placeID: seed.place?.id, tier: seed.tier, userSet: seed.tier == .exact,
                    addSeenStart: start, addSeenEnd: start.addingTimeInterval(21 * 60), computedAt: now
                ).save(db)
            }
            try Person(contactID: "rhea", name: "Rhea Sethi", beforeInstall: true, createdAt: daysAgo(60, hour: 9)).save(db)
        }
    }
}
