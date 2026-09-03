import Foundation

/// Which kind of build this is, the way mixbridge tells them apart: Xcode sets DEBUG, TestFlight
/// installs a sandbox receipt, and the App Store is whatever is left.
enum BuildEnvironment {
    case debug
    case testFlight
    case appStore

    static let current: BuildEnvironment = {
        #if DEBUG
            return .debug
        #else
            if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
                return .testFlight
            }
            return .appStore
        #endif
    }()

    /// Debug and TestFlight builds get the tools; the App Store build never sees them.
    static var isDev: Bool {
        current != .appStore
    }
}
