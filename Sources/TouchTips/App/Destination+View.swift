import SwiftUI

/// The one place a destination becomes a screen.
struct DestinationView: View {
    let destination: Destination
    /// The namespace holding the row's `matchedTransitionSource`, when the push should zoom.
    var zoom: Namespace.ID?

    var body: some View {
        switch destination {
        case let .person(contactID):
            if let zoom {
                PersonView(contactID: contactID)
                    .navigationTransition(.zoom(sourceID: contactID, in: zoom))
            } else {
                PersonView(contactID: contactID)
            }
        }
    }
}
