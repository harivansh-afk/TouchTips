import SwiftUI

/// A Phosphor glyph from the asset catalog, sized the way mixbridge sizes its row icons.
/// Tabs use the raw `Image(name)` like mixbridge does; everything else goes through here.
struct Icon: View {
    let name: String
    var size: CGFloat = 20

    init(_ name: String, size: CGFloat = 20) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
