import SwiftUI

/// The palette, all of it. Pure black ground, white type, three whites at fixed opacities, and
/// one quiet green for a place that is known. Surfaces are glass or nothing, so there are no
/// grey fills to name.
extension Color {
    /// The ground under everything.
    static let ground = Color.black
    /// Row separators. Twelve percent, per the design doc.
    static let hairline = Color.white.opacity(0.12)
    /// The tab bar's selection pill.
    static let pill = Color.white.opacity(0.14)
    /// Dashed outlines that mean "nothing chosen yet".
    static let dashed = Color.white.opacity(0.35)
    /// A place on the map: the chosen spot's dot and the ring around a person's pin. Sage, not signal.
    static let placed = Color(hue: 0.36, saturation: 0.38, brightness: 0.74)
}
