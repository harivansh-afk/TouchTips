import Lottie
import SwiftUI

@main
struct TouchTipsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // Splash state management
    @State private var finishedSplash: Bool = false
    @State private var isAppInitialized: Bool = false

    // Splash is visible until both animation and app initialization are complete
    private var isShowingSplash: Bool {
        !(isAppInitialized && finishedSplash)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isAppInitialized {
                    RootView()
                }

                splashView
            }
            .preferredColorScheme(.dark)
            .environment(delegate.app)
            .onAppear {
                // Minimum splash display time. Capture already started in AppDelegate.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    isAppInitialized = true
                }
            }
        }
    }

    private var splashView: some View {
        SplashView {
            Task { @MainActor in
                // Optional: add slight delay after animation completes
                try? await Task.sleep(for: .milliseconds(200))
                finishedSplash = true
                // Completion triggers splash fade-out via isShowingSplash
            }
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
            Color.black.ignoresSafeArea()

            LottieView(
                file: .logo,
                loopMode: .playOnce,
                speed: 1.5,
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
