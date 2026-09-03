import MapKit
import SwiftUI

/// Four pictures of the block you are looking at, one per style. Tap one and the map behind
/// changes at once; the sheet is the confirmation. Swipe down to leave.
struct MapStylesSheet: View {
    let region: MKCoordinateRegion
    @Binding var choice: MapStyleChoice
    /// The grid's measured height, so the sheet can be exactly that plus equal padding.
    @Binding var contentHeight: CGFloat

    @Environment(MapSnapshots.self) private var snapshots

    static let padding: CGFloat = 24
    static let tileSize = CGSize(width: 160, height: 108)

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
            ForEach(MapStyleChoice.allCases) { option in
                tile(option)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .padding(.horizontal, 20)
        .padding(.vertical, Self.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .task { snapshots.prefetch(region: region) }
    }

    private func tile(_ option: MapStyleChoice) -> some View {
        let selected = choice == option
        return Button {
            HapticManager.selection()
            choice = option
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    option.ground
                    if let image = snapshots.image(for: option, region: region) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .grayscale(option == .muted ? 1 : 0)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: snapshots.image(for: option, region: region) != nil)
                .aspectRatio(Self.tileSize.width / Self.tileSize.height, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(selected ? Color.white : Color.hairline, lineWidth: selected ? 2 : 1)
                }
                Text(option.title)
                    .font(.footnote.weight(selected ? .medium : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.press)
        .animation(.snappy, value: selected)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
