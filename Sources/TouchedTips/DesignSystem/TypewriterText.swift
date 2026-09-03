import SwiftUI

/// A headline that types itself. The whole string is laid out once and the renderer draws its
/// glyphs one at a time, each rising out of a blur, so the serif keeps its kerning and nothing
/// reflows mid-word.
///
/// The rhythm: letters at a steady pace, spaces a touch longer. Before a question mark the typing
/// hesitates, then the mark rises slowly from further down and lands with a heavy haptic. Every
/// other glyph is a light tick. Flip `leaving` and the glyphs sweep back out in the order they came.
struct TypewriterText: View {
    let text: String
    let font: Font
    var leaving = false
    /// Runs once, on the main actor, after the last glyph has landed.
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = GlyphReveal.Progress()

    var body: some View {
        Text(text)
            .font(font)
            .textRenderer(GlyphReveal(progress: progress))
            .task { await type() }
            .onChange(of: leaving) { _, leaving in
                guard leaving else { return }
                withAnimation(.easeIn(duration: 0.55)) { progress.exit = 1 }
            }
    }

    /// A held breath on the empty screen before the first glyph.
    private static let leadIn: Duration = .milliseconds(700)
    private static let letter: Duration = .milliseconds(52)
    private static let space: Duration = .milliseconds(100)
    /// The pause before a question mark, as if deciding to ask.
    private static let hesitation: Duration = .milliseconds(220)
    /// How far into the mark's rise the heavy haptic lands.
    private static let landing: Duration = .milliseconds(340)
    /// After a mark lands, before the next line starts.
    private static let linePause: Duration = .milliseconds(560)

    private func type() async {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if reduceMotion {
            progress = .complete
            onFinished()
            return
        }
        try? await Task.sleep(for: Self.leadIn)
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 {
                try? await Task.sleep(for: Self.linePause)
                progress = .start(ofLine: lineIndex)
            }
            for glyph in line {
                guard !Task.isCancelled else { return }
                if glyph == "?" {
                    try? await Task.sleep(for: Self.hesitation)
                    progress.slow = true
                    withAnimation(.easeOut(duration: 0.6)) { progress.glyphs += 1 }
                    HapticManager.light()
                    try? await Task.sleep(for: Self.landing)
                    HapticManager.heavy()
                } else {
                    progress.slow = false
                    withAnimation(.easeOut(duration: 0.22)) { progress.glyphs += 1 }
                    if !glyph.isWhitespace {
                        HapticManager.light()
                    }
                    try? await Task.sleep(for: glyph.isWhitespace ? Self.space : Self.letter)
                }
            }
        }
        progress = .complete
        onFinished()
    }
}

/// Draws every line before `progress.line` in full, the glyphs of that line up to
/// `progress.glyphs` (the last one part-way in), and nothing after. `exit` sweeps every drawn
/// glyph back out, first typed first gone.
private struct GlyphReveal: TextRenderer, Animatable {
    struct Progress {
        var line = 0
        var glyphs = 0.0
        /// The glyph entering right now takes the long way in: further to rise, deeper blur.
        var slow = false
        var exit = 0.0

        static func start(ofLine line: Int) -> Progress {
            Progress(line: line, glyphs: 0)
        }

        static let complete = Progress(line: .max, glyphs: 0)
    }

    var progress: Progress

    /// The glyph count and the exit sweep interpolate; the line index steps.
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress.glyphs, progress.exit) }
        set {
            progress.glyphs = newValue.first
            progress.exit = newValue.second
        }
    }

    /// How many glyphs are mid-sweep at once on the way out.
    private static let sweep = 8.0

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let lines = layout.map { Array($0.flatMap(\.self)) }
        let total = Double(lines.reduce(0) { $0 + $1.count })
        var index = 0.0
        for (lineIndex, slices) in lines.enumerated() {
            if lineIndex > progress.line {
                return
            }
            for (glyphIndex, slice) in slices.enumerated() {
                let entered = lineIndex < progress.line ? 1 : unit(progress.glyphs - Double(glyphIndex))
                guard entered > 0 else { break }
                let gone = unit((progress.exit * (total + Self.sweep) - index) / Self.sweep)
                index += 1
                let visible = entered * (1 - gone)
                guard visible > 0 else { continue }
                let rise = progress.slow && entered < 1 ? 18.0 : 10.0
                let haze = progress.slow && entered < 1 ? 10.0 : 6.0
                var glyph = context
                glyph.opacity = visible
                glyph.translateBy(x: 0, y: (1 - entered) * rise - gone * 14)
                if visible < 1 {
                    glyph.addFilter(.blur(radius: (1 - entered) * haze + gone * 8))
                }
                glyph.draw(slice)
            }
        }
    }

    private func unit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

#Preview {
    TypewriterText(text: "Who did I meet?\nWhere did I meet them?\nWhen?", font: .display(40))
        .foregroundStyle(.white)
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.ground)
}
