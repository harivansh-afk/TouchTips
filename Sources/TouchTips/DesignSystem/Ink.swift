import SwiftUI

/// The palette, all of it. Pure black ground, white type, and three whites at fixed opacities.
/// Surfaces are glass or nothing, so there are no grey fills to name.
extension Color {
    /// The ground under everything.
    static let ground = Color.black
    /// Row separators. Twelve percent, per the design doc.
    static let hairline = Color.white.opacity(0.12)
    /// The tab bar's selection pill.
    static let pill = Color.white.opacity(0.14)
    /// Dashed outlines that mean "nothing chosen yet".
    static let dashed = Color.white.opacity(0.35)
}
