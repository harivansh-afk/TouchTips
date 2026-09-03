import SwiftUI

/// Four pictures, one per style, of the same blocks of lower Manhattan, rendered once on a Mac
/// and shipped as assets so the sheet is instant. Tap one and the map behind changes at once;
/// the sheet is the confirmation. Swipe down to leave.
struct MapStylesSheet: View {
    @Binding var choice: MapStyleChoice
    /// The grid's measured height, so the sheet can be exactly that plus equal padding.
    @Binding var contentHeight: CGFloat

    static let padding: CGFloat = 24
    private static let tileAspect: CGFloat = 160 / 108

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
