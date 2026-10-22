import SwiftUI

/// Text that arrives rather than appears.
///
/// An Amazon charge starts out saying "Shopping" and becomes "Naked Whey Isolate Protein" the moment its order is
/// read — which can happen while you're looking straight at it. Swapping the words in one frame reads as a glitch;
/// letting them resolve reads as an answer arriving. The feel is iMessage's invisible ink: the words emerge from a
/// haze, left to right, as it clears.
///
/// Only a *change* animates. Scrolling a row back on screen is not news, so text that was already settled is drawn
/// plainly — otherwise the whole feed would shimmer every time it moved.
struct RevealingText: View {
    let text: String

    @State private var shown = ""
    @State private var reveal: Double = 1

    var body: some View {
        Text(shown)
            .textRenderer(InkRenderer(reveal: reveal))
            .onAppear { if shown.isEmpty { shown = text } }
            .onChange(of: text) { previous, now in
                shown = now
                // Nothing to reveal if there was nothing there before — that's an arrival, not a change.
                guard !previous.isEmpty else { return }
                reveal = 0
                withAnimation(.easeOut(duration: 0.85)) { reveal = 1 }
            }
    }
}

/// Draws each glyph out of a blur, in a wave from the start of the line to the end.
private struct InkRenderer: TextRenderer, Animatable {
    var reveal: Double

    var animatableData: Double {
        get { reveal }
        set { reveal = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let glyphs = layout.flatMap { $0 }.flatMap { $0 }
        guard !glyphs.isEmpty else { return }
        // Each glyph waits its turn, and they overlap — a wave across the line rather than a row of separate pops.
        let stagger = 0.55 / Double(glyphs.count)
        for (i, glyph) in glyphs.enumerated() {
            let begun = reveal - Double(i) * stagger
            let t = min(max(begun / 0.45, 0), 1)
            var copy = context
            copy.opacity = t
            if t < 1 {
                copy.addFilter(.blur(radius: (1 - t) * 3.5))
                copy.translateBy(x: 0, y: (1 - t) * 1.5)
            }
            copy.draw(glyph)
        }
    }
}
