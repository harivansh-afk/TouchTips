import SwiftUI

extension Font {
    /// The one display face. One word or line per screen, never body text.
    static func display(_ size: CGFloat) -> Font {
        .custom("InstrumentSerif-Italic", size: size)
    }
}

extension View {
    /// A screen or sheet title set in the display face. `navigationTitle` stays underneath for
    /// VoiceOver and back labels; the principal item is what the eye sees.
    func serifTitle(_ title: String, subtitle: String? = nil) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(title).font(.display(22))
                        if let subtitle {
                            Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
    }
}
