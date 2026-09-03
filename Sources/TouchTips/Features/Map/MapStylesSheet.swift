import MapKit
import SwiftUI

/// Four pictures of the block you are looking at, one per style. Tap one and the map behind
/// changes at once; the sheet is the confirmation.
struct MapStylesSheet: View {
    let region: MKCoordinateRegion
    @Binding var choice: MapStyleChoice

    @State private var snapshots = MapSnapshots()

    private static let tileSize = CGSize(width: 160, height: 108)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Map")
                .font(.display(28))
                .padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                ForEach(MapStyleChoice.allCases) { option in
                    tile(option)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.ground)
        .task {
            for option in MapStyleChoice.allCases {
                snapshots.load(option, region: region, size: Self.tileSize)
            }
        }
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
                    }
                }
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
