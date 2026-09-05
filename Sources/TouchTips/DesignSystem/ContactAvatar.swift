import SwiftUI

/// The contact's photo if Contacts has one, otherwise their initials in glass.
struct ContactAvatar: View {
    @Environment(AppModel.self) private var app
    let contactID: String
    let initials: String
    var size: CGFloat = 42

    var body: some View {
        Group {
            if let image = app.photos.image(for: contactID) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(.circle)
            } else {
                InitialsAvatar(initials: initials, size: size)
            }
        }
        .task(id: app.photos.loadID(for: contactID)) { await app.photos.load(contactID) }
    }
}
