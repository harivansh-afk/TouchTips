import SwiftUI

/// A headline that types itself. The whole string is laid out once and the renderer draws its
/// glyphs one at a time, each rising out of a blur, so the serif keeps its kerning and nothing
/// reflows mid-word.
///
/// The run is scheduled up front: every glyph gets a time, the haptics for the whole run go to
/// CoreHaptics as one pattern, and the glyphs are drawn against the same clock. Letters come at a
/// steady pace, spaces a touch longer. Before a question mark the typing hesitates, then the mark
/// rises slowly from further down and lands with a thud. Flip `leaving` and the glyphs sweep back
/// out in the order they came.
struct TypewriterText: View {
    let text: String
    let font: Font
    var leaving = false
    /// Runs once, on the main actor, after the last glyph has landed.
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = GlyphReveal.Progress()
    @State private var haptics = TypingHaptics()

    var body: some View {
        Text(text)
            .font(font)
            .textRenderer(GlyphReveal(progress: progress))
            .task { await type() }
            .onChange(of: leaving) { _, leaving in
                guard leaving else { return }
                withAnimation(.easeIn(duration: 0.38)) { progress.exit = 1 }
            }
    }

    /// One glyph and the moment it lands, in seconds from the start of the run.
    private struct Step {
        let line: Int
        let glyph: Character
        let at: TimeInterval
    }

    /// A held breath on the empty screen before the first glyph.
    private static let leadIn: TimeInterval = 0.5
    private static let letter: TimeInterval = 0.046
    private static let space: TimeInterval = 0.08
    /// The pause before a question mark, as if deciding to ask.
    private static let hesitation: TimeInterval = 0.16
    /// How long a question mark takes to rise.
    private static let markRise: TimeInterval = 0.4
    /// How far into the rise the thud lands.
    private static let landing: TimeInterval = 0.2
    /// After a mark lands, before the next line starts.
    private static let linePause: TimeInterval = 0.3

    private static func schedule(_ lines: [Substring]) -> (steps: [Step], end: TimeInterval) {
        var steps: [Step] = []
        var time = leadIn
        for (line, glyphs) in lines.enumerated() {
            if line > 0 {
                time += linePause
            }
            for glyph in glyphs {
                if glyph == "?" {
                    time += hesitation
                }
                steps.append(Step(line: line, glyph: glyph, at: time))
                time += glyph == "?" ? markRise : glyph.isWhitespace ? space : letter
            }
        }
        return (steps, time)
    }

    private static func taps(for steps: [Step]) -> [TypingHaptics.Tap] {
        steps.flatMap { step -> [TypingHaptics.Tap] in
            if step.glyph == "?" {
                return [.strike(at: step.at), .thud(at: step.at + landing)]
            }
            return step.glyph.isWhitespace ? [] : [.tick(at: step.at)]
        }
    }

    private func type() async {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if reduceMotion {
            progress = .complete
            onFinished()
            return
        }
        let (steps, end) = Self.schedule(lines)
        haptics.prepare()
        let clock = ContinuousClock()
        let start = clock.now
        haptics.play(Self.taps(for: steps))
        var line = 0
        for step in steps {
            try? await clock.sleep(until: start + .seconds(step.at))
            guard !Task.isCancelled else { return }
            if step.line != line {
                line = step.line
                progress = .start(ofLine: line)
            }
            progress.slow = step.glyph == "?"
            withAnimation(.easeOut(duration: step.glyph == "?" ? Self.markRise : 0.18)) { progress.glyphs += 1 }
        }
        try? await clock.sleep(until: start + .seconds(end))
        guard !Task.isCancelled else { return }
        progress = .complete
        onFinished()
    }
}

/// Draws every line before `progress.line` in full, the glyphs of that line up to
/// `progress.glyphs` (the last one part-way in), and nothing after. `exit` sweeps every drawn
/// glyph back out, first typed first gone. Blur is only paid on the way in, one glyph at a time;
/// on the way out a dozen glyphs move at once, so they fade and drift instead.
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
    private static let sweep = 12.0

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
                glyph.translateBy(x: 0, y: (1 - entered) * rise - gone * 12)
                if entered < 1 {
                    glyph.addFilter(.blur(radius: (1 - entered) * haze))
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
