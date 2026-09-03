import SwiftUI

// Whole screens against the seeded in-memory model. Rendered only by Xcode's canvas.

#Preview("People") {
    PeopleView()
        .environment(AppModel.preview)
        .environment(Router())
        .preferredColorScheme(.dark)
}

#Preview("Person") {
    NavigationStack {
        PersonView(contactID: "maya")
    }
    .environment(AppModel.preview)
    .environment(Router())
    .preferredColorScheme(.dark)
}

#Preview("Map") {
    MapScreen()
        .environment(AppModel.preview)
        .environment(Router())
        .preferredColorScheme(.dark)
}

#Preview("Settings") {
    SettingsSheet()
        .environment(AppModel.preview)
        .environment(Router())
        .preferredColorScheme(.dark)
}
