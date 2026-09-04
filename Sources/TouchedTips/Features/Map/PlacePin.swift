import SwiftUI
import TouchedTipsCore

/// What one pin stands for: a place, or several whose pins would overlap at the map's current
/// zoom. Zooming in splits a group back into its places.
struct PlaceGroup: Hashable, Identifiable {
    /// Sorted by id, so the same places make the same group whatever order they came in.
    let places: [PlaceSummary]

    init(places: [PlaceSummary]) {
        self.places = places.sorted { $0.id < $1.id }
    }

    var id: String { places.map { String($0.id) }.joined(separator: "-") }
    var people: Int { places.reduce(0) { $0 + $1.people } }
    var witnessed: Bool { places.contains(where: \.witnessed) }
    var first: Date { places.map(\.first).min() ?? .distantPast }
    var last: Date { places.map(\.last).max() ?? .distantPast }
    /// The one person met here, when the group is one place with one person.
    var soleContactID: String? { places.count == 1 ? places[0].soleContactID : nil }
    var soleName: String? { places.count == 1 ? places[0].soleName : nil }

    /// One place is its name; more are counted.
    var title: String {
        if places.count == 1 {
            let place = places[0]
            return place.name ?? Format.coordinates(place.latitude, place.longitude)
        }
        return "\(places.count) places"
    }
}

/// A pin on the map. One person is drawn as themselves, their photo or initials; more than one
/// is a count. The ring takes the map style's tint, solid when someone was witnessed here and
/// faint when only inferred.
struct PlacePin: View {
    let group: PlaceGroup
    /// The sole person's contact photo, when Contacts has one and it has loaded.
    var image: UIImage?
    var tint: Color
    var selected = false

    private var size: CGFloat { group.soleContactID == nil ? 44 : 40 }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(.circle)
            } else if let name = group.soleName {
                InitialsAvatar(initials: Person.initials(for: name), size: size)
            } else {
                Text(group.people, format: .number)
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .glassEffect(.clear, in: .circle)
            }
        }
        // The shadow hangs off the ring, not the pin: a shadow on the glass itself rasterises it,
        // and the glass goes flat and frosted instead of showing the map through.
        .overlay {
            Circle()
                .strokeBorder(tint.opacity(group.witnessed ? 1 : 0.45), lineWidth: 2)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
        }
        .scaleEffect(selected ? 1.15 : 1)
        .animation(.appleInteractive, value: selected)
        .accessibilityLabel(group.soleName ?? "\(group.people) people")
    }
}
