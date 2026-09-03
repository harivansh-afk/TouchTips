import SwiftUI

/// A headline that types itself. The whole string is laid out once and the renderer draws its
/// glyphs one at a time, each rising out of a blur, so the serif keeps its kerning and nothing
/// reflows mid-word. Every glyph is a light tick; a question mark lands heavy.
struct TypewriterText: View {
    let text: String
    let font: Font
    /// Runs once, on the main actor, after the last glyph has landed.
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = GlyphReveal.Progress()

    var body: some View {
        Text(text)
            .font(font)
            .textRenderer(GlyphReveal(progress: progress))
            .task { await type() }
    }

    private static let glyphPause: Duration = .milliseconds(42)
    private static let spacePause: Duration = .milliseconds(90)
    private static let linePause: Duration = .milliseconds(360)

    private func type() async {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if reduceMotion {
            progress = .complete
            onFinished()
            return
        }
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 {
                progress = .start(ofLine: lineIndex)
                try? await Task.sleep(for: Self.linePause)
            }
            for glyph in line {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.16)) { progress.glyphs += 1 }
                if glyph == "?" {
                    HapticManager.heavy()
                } else if !glyph.isWhitespace {
                    HapticManager.light()
                }
                try? await Task.sleep(for: glyph.isWhitespace ? Self.spacePause : Self.glyphPause)
            }
        }
        progress = .complete
        onFinished()
    }
}

/// Draws every line before `progress.line` in full, the glyphs of that line up to
/// `progress.glyphs` (the last one part-way in), and nothing after.
private struct GlyphReveal: TextRenderer, Animatable {
    struct Progress {
        var line = 0
        var glyphs = 0.0

        static func start(ofLine line: Int) -> Progress {
            Progress(line: line, glyphs: 0)
        }

        static let complete = Progress(line: .max, glyphs: 0)
    }

    var progress: Progress

    /// Only the glyph count interpolates; the line index steps.
    var animatableData: Double {
        get { progress.glyphs }
        set { progress.glyphs = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for (lineIndex, line) in layout.enumerated() {
            if lineIndex > progress.line {
                return
            }
            for (glyphIndex, slice) in line.flatMap(\.self).enumerated() {
                let t = lineIndex < progress.line ? 1 : min(max(progress.glyphs - Double(glyphIndex), 0), 1)
                guard t > 0 else { break }
                var glyph = context
                glyph.opacity = t
                glyph.translateBy(x: 0, y: (1 - t) * 10)
                if t < 1 {
                    glyph.addFilter(.blur(radius: (1 - t) * 6))
                }
                glyph.draw(slice)
            }
        }
    }
}

#Preview {
    TypewriterText(text: "Who did I meet?\nWhere did I meet them?\nWhen?", font: .display(40))
        .foregroundStyle(.white)
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.ground)
}
