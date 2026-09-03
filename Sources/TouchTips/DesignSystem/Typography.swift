import SwiftUI

extension Font {
    /// The one display face. One word or line per screen, never body text.
    static func display(_ size: CGFloat) -> Font {
        .custom("InstrumentSerif-Italic", size: size)
    }
}
