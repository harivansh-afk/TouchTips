import SwiftUI
import UIKit

/// The first-run screen, in two parts on one black. First the three questions type themselves
/// and Contacts and Location rise in under them. Then, once those have left, one line says what
/// happens when you meet someone, the notice the phone will send drops in where a real one
/// would, and Notifications is asked for right there. Continue sends it all away in the order it came.
///
/// Contract with `RootView`: call `finish` the moment the last Continue is tapped and start
/// leaving at once. The app begins rising in 0.25 seconds later and this screen is removed 0.75
/// seconds after the call, so whatever it is still drawing by then must be gone. The ground goes
/// clear on the way out; the app underneath is the same black.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.splashShowing) private var splashShowing
    @AppStorage(OnboardingAccess.pretendKey) private var pretend = false
    let finish: () -> Void

    private enum Part: Int, CaseIterable {
        case questions, notice
    }

    @State private var part = Part.questions
    /// Flips on the last Continue; the ground clears and the app underneath is revealed.
    @State private var gone = false
    @State private var pretendGranted: Set<Permission> = []

    private var access: OnboardingAccess {
        OnboardingAccess(app: app, pretend: pretend, pretendGranted: $pretendGranted)
    }

    var body: some View {
        ZStack {
            switch part {
            case .questions:
                QuestionsPart(access: access) {
                    // The questions have swept out; the next part starts on the cleared black.
                    part = .notice
                }
            case .notice:
                NoticePart(access: access) {
                    gone = true
                    finish()
                }
            }
        }
        .overlay(alignment: .top) {
            PartDots(count: Part.allCases.count, current: part.rawValue)
                .padding(.top, 6)
                .opacity(splashShowing || gone ? 0 : 1)
                .animation(.easeOut(duration: 0.3), value: splashShowing || gone)
        }
        // Edge to edge: this is an overlay on the finished app, nothing may show around it. Clear
        // the instant it starts leaving; the app under it is the same black, so nothing changes.
        .background { Color.ground.opacity(gone ? 0 : 1).ignoresSafeArea() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                access.refresh()
            }
        }
    }
}

/// Where you are in the screen: one small dot a part, the current one lit. Sits under the
/// island, quiet enough to miss.
private struct PartDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< count, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(index == current ? 0.7 : 0.22))
                    .frame(width: 5, height: 5)
            }
        }
        .animation(.smooth(duration: 0.4), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Part \(current + 1) of \(count)")
    }
}

/// Hidden until `shown`, then fades up into place, `order` beats after its siblings. On
/// `leaving` the last part drops first and the rest follow it down, bottom to top, so the
/// headline's sweep starts on a cleared screen. `last` is the highest order on the screen.
private struct Staged: ViewModifier {
    let shown: Bool
    let leaving: Bool
    let order: Int
    let last: Int

    func body(content: Content) -> some View {
        let visible = shown && !leaving
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 14)
            .allowsHitTesting(visible)
            .animation(
                leaving
                    ? .easeIn(duration: 0.2).delay(Double(last - order) * 0.03)
                    : .spring(response: 0.45, dampingFraction: 0.85).delay(Double(order) * 0.07),
                value: visible
            )
    }
}

private extension View {
    func staged(_ shown: Bool, leaving: Bool, order: Int, last: Int) -> some View {
        modifier(Staged(shown: shown, leaving: leaving, order: order, last: last))
    }
}

/// The one full-width button on the screen, in the same clear glass as everything else.
private struct ContinueButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Continue")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }
}

/// The three questions, then Contacts and Location under them.
private struct QuestionsPart: View {
    @Environment(\.splashShowing) private var splashShowing
    let access: OnboardingAccess
    /// Called once the headline has swept out, so the next part starts on an empty screen.
    let done: () -> Void

    private static let permissions: [Permission] = [.contacts, .location]

    /// Flips once the headline has finished typing; everything under it rises in after.
    @State private var revealed = false
    /// Flips on Continue; everything falls away and the headline sweeps out on its heels.
    @State private var leaving = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(26)
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task(id: revealed) {
            guard revealed, OnboardingAccess.autoplay else { return }
            for permission in Self.permissions {
                try? await Task.sleep(for: .seconds(1.2))
                access.request(permission)
            }
            try? await Task.sleep(for: .seconds(1.6))
            leave()
        }
    }

    private func leave() {
        HapticManager.heavy()
        leaving = true
        Task {
            // The rows are down by 0.3 s and the last glyph is gone by 0.4 s.
            try? await Task.sleep(for: .milliseconds(460))
            done()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            TypewriterText(
                text: "Who did I meet?\nWhere did I meet them?\nWhen?",
                font: .display(40),
                begin: !splashShowing,
                leaving: leaving
            ) {
                revealed = true
            }
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)

            Text("Remember when and where you met your contacts.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
                .staged(revealed, leaving: leaving, order: 0, last: 3)

            ForEach(Array(Self.permissions.enumerated()), id: \.element) { index, permission in
                PermissionRow(permission: permission, access: access)
                    .staged(revealed, leaving: leaving, order: index + 1, last: 3)
            }

            Spacer()
            ContinueButton(action: leave)
                .staged(revealed, leaving: leaving, order: 3, last: 3)
        }
    }
}

/// What happens when you meet someone: the notice drops in where a real one would, one line
/// under it says so, and Notifications is asked for right there.
private struct NoticePart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let access: OnboardingAccess
    /// Called the moment Continue is tapped, as this part starts leaving.
    let finish: () -> Void

    @State private var revealed = false
    /// The notice has dropped in. A beat after the line, with the tap a real one gives.
    @State private var noticed = false
    @State private var leaving = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(26)
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .overlay(alignment: .top) {
            NoticeBanner()
                .padding(.horizontal, 8)
                .padding(.top, 20)
                .opacity(noticed && !leaving ? 1 : 0)
                .offset(y: noticed && !leaving ? 0 : reduceMotion ? 0 : -44)
                .animation(
                    leaving ? .easeIn(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.78),
                    value: noticed && !leaving
                )
                .accessibilityHidden(!noticed)
        }
        .task(id: revealed) {
            guard revealed else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !leaving else { return }
            noticed = true
            HapticManager.success()
            guard OnboardingAccess.autoplay else { return }
            try? await Task.sleep(for: .seconds(1.2))
            access.request(.notifications)
            try? await Task.sleep(for: .seconds(1.6))
            leave()
        }
    }

    private func leave() {
        HapticManager.heavy()
        leaving = true
        finish()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            TypewriterText(
                text: "When you meet someone new,\nwe'll let you know.",
                font: .display(40),
                leaving: leaving
            ) {
                revealed = true
            }
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)

            // One sentence a line, as few words as each will take.
            Text("Once you save their contact,\na notification will confirm the time and place.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
                .staged(revealed, leaving: leaving, order: 0, last: 2)

            PermissionRow(permission: .notifications, access: access)
                .staged(revealed, leaving: leaving, order: 1, last: 2)

            Spacer()
            ContinueButton(action: leave)
                .staged(revealed, leaving: leaving, order: 2, last: 2)
        }
    }
}

/// The notice as the phone shows one: the app's icon, the title the app really sends, the place
/// and time in its own format, and "now" in the corner. Frosted like a real banner, not clear.
private struct NoticeBanner: View {
    private static let name = "Erlich Bachman"

    private var body_: String {
        Format.notice(placeName: "Grit Coffee", at: .now)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AppIcon(size: 38)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Met \(Self.name)?")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("now")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(body_)
                    .font(.subheadline)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notification: Met \(Self.name)? \(body_)")
    }
}

/// The app's own icon, read from the bundle the way the system shows it on a notice.
private struct AppIcon: View {
    let size: CGFloat

    private static let image: UIImage? = {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last else { return nil }
        return UIImage(named: name)
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                InitialsAvatar(initials: "TT", size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.22))
        .accessibilityHidden(true)
    }
}
