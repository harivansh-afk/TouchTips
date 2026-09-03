import SwiftUI

/// A Phosphor glyph from the asset catalog, sized the way mixbridge sizes its row icons.
/// Xcode generates an `ImageResource` per imageset, so a misspelt glyph is a build error.
/// Tabs use the raw `Image(resource)` like mixbridge does; everything else goes through here.
struct Icon: View {
    let resource: ImageResource
    var size: CGFloat = 20

    init(_ resource: ImageResource, size: CGFloat = 20) {
        self.resource = resource
        self.size = size
    }

    var body: some View {
        Image(resource)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
