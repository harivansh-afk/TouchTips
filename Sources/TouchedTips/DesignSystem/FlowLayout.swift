import SwiftUI

/// Chips in rows, wrapping at the right edge, so a place with a long name or a day with many
/// stays visible instead of hiding in a horizontal scroll.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        place(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = place(in: bounds.width, subviews: subviews)
        for (index, slot) in result.slots.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + slot.origin.x, y: bounds.minY + slot.origin.y),
                proposal: slot.proposal
            )
        }
    }

    private struct Slot {
        let origin: CGPoint
        /// What the subview was measured with, so it is placed at the size it was measured at.
        let proposal: ProposedViewSize
    }

    /// Every subview at its own width, but never wider than a row: one that would not fit on a row
    /// of its own is proposed the row's width and truncates, instead of pushing the whole screen
    /// wider than the viewport. The reported width is capped the same way.
    private func place(in width: CGFloat, subviews: Subviews) -> (size: CGSize, slots: [Slot]) {
        var slots: [Slot] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            var proposal = ProposedViewSize.unspecified
            var size = subview.sizeThatFits(proposal)
            if size.width > width {
                proposal = ProposedViewSize(width: width, height: nil)
                size = subview.sizeThatFits(proposal)
                size.width = min(size.width, width)
            }
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            slots.append(Slot(origin: CGPoint(x: x, y: y), proposal: proposal))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: min(maxX, width), height: y + rowHeight), slots)
    }
}
