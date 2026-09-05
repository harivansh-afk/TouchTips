import SwiftUI

extension View {
    @ViewBuilder
    func personTransitionSource(id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}

/// The one place a destination becomes a screen.
struct DestinationView: View {
    let destination: Destination
    /// The namespace holding the row's `matchedTransitionSource`, when the push should zoom.
    var zoom: Namespace.ID?

    var body: some View {
        switch destination {
        case let .person(contactID, zoom: wantsZoom):
            if let zoom, wantsZoom {
                PersonView(contactID: contactID)
                    .navigationTransition(.zoom(sourceID: contactID, in: zoom))
            } else {
                PersonView(contactID: contactID)
            }
        case .undocumented:
            UndocumentedView()
        }
    }
}
