import SwiftUI
import TouchedTipsCore

/// A place on the map. One person is drawn as themselves, their photo or initials; more than one
/// is a count. The ring takes the map style's tint, solid when someone was witnessed here and
/// faint when only inferred.
struct PlacePin: View {
    let place: PlaceSummary
    /// The sole person's contact photo, when Contacts has one and it has loaded.
    var image: UIImage?
    var tint: Color
    var selected = false

    private var size: CGFloat { place.soleContactID == nil ? 44 : 40 }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(.circle)
            } else if let name = place.soleName {
                InitialsAvatar(initials: Person.initials(for: name), size: size)
            } else {
                Text(place.people, format: .number)
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .glassEffect(.clear, in: .circle)
            }
        }
        .overlay {
            Circle().strokeBorder(tint.opacity(place.witnessed ? 1 : 0.45), lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
        .scaleEffect(selected ? 1.15 : 1)
        .animation(.appleInteractive, value: selected)
        .accessibilityLabel(place.soleName ?? "\(place.people) people")
    }
}
