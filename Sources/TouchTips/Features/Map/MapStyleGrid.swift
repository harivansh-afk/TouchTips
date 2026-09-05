import SwiftUI

/// Four pictures, one per style, of the same blocks of lower Manhattan, rendered once on a Mac
/// and shipped as assets. Lives in Settings; tapping one changes the map the next time it is seen.
struct MapStyleGrid: View {
    @Binding var choice: MapStyleChoice

    private static let tileAspect: CGFloat = 160 / 108

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
            ForEach(MapStyleChoice.allCases) { option in
                tile(option)
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
                Image(option.preview)
                    .resizable()
                    .aspectRatio(Self.tileAspect, contentMode: .fit)
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
