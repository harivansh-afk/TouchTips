import SwiftUI

struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 42

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .glassEffect(.clear, in: .circle)
    }
}
