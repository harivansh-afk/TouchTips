import Lottie
import SwiftUI

@main
struct TouchedTipsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    // Splash state. The wordmark plays once per process, so a warm launch never sees it.
    @State private var finishedSplash: Bool = false
    /// A floor against a flash on a fast device; nothing else waits on it.
    @State private var pastFloor: Bool = false

    private var isShowingSplash: Bool {
        !(pastFloor && finishedSplash)
    }

    /// The wordmark plays for one second. A process that CoreLocation launched in the background may never
    /// get the animation's completion, so the first active scene also ends the splash on a clock.
    private static let splashCap: Duration = .milliseconds(1400)

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Laid out under the splash from the start, so the fade reveals a finished screen.
                RootView()

                splashView
            }
            .preferredColorScheme(.dark)
            .environment(delegate.app)
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    pastFloor = true
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active, !finishedSplash else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: Self.splashCap)
                    finishedSplash = true
                }
            }
        }
    }

    private var splashView: some View {
        SplashView {
            // The fade starts the instant the animation ends.
            finishedSplash = true
        }
        .opacity(isShowingSplash ? 1 : 0)
        .allowsHitTesting(isShowingSplash)
        .animation(.easeInOut(duration: 0.2), value: isShowingSplash)
    }
}

private struct SplashView: View {
    var onFinished: () -> Void
    /// logo.json is a 205 by 73 composition.
    private let splashAspectRatio: CGFloat = 73.0 / 205.0

    var body: some View {
        GeometryReader { proxy in
            content(for: proxy.size)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func content(for size: CGSize) -> some View {
        // custom padding for position
        let availableWidth = max(size.width - 250, 120)
        let width = min(availableWidth, 320)
        let height = width * splashAspectRatio

        ZStack {
            Color.ground.ignoresSafeArea()

            LottieView(
                file: .logo,
                loopMode: .playOnce,
                speed: 2.0,
                onComplete: {
                    onFinished()
                }
            )
            .frame(width: width, height: height)
            .compositingGroup()
            .colorInvert()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
