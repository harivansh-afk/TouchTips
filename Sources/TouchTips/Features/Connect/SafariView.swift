// An in-app Safari sheet for clients whose iOS app can't take a server, so the web page is the way in.

import SafariServices
import SwiftUI

struct WebDestination: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = .white
        controller.preferredBarTintColor = .black
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
