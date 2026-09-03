import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Binding var done: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Where did\nyou meet\neveryone?")
                .font(.display(52))
                .lineSpacing(-2)
            Text("touchtips watches new contacts and your visits, and remembers when and where each person came in. Nothing leaves this phone.")
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            PermissionRow(
                title: "Contacts",
                detail: "Full access, so new people can be noticed.",
                granted: app.contactsAccess.granted
            ) {
                Task {
                    await app.contactsAccess.request()
                    app.capture.scheduleTick()
                }
            }
            PermissionRow(
                title: "Location, Always",
                detail: "Visits wake the app and give the place.",
                granted: app.capture.locationGranted
            ) {
                app.capture.requestLocation()
            }

            Spacer()
            Button {
                done = true
            } label: {
                Text("Start").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .controlSize(.large)
        }
        .padding(26)
        .background(Color.black)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.contactsAccess.refresh() }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(granted ? "Allowed" : "Allow", action: action)
                .buttonStyle(.glass)
                .disabled(granted)
        }
        .padding(16)
        .glassEffect(.clear, in: .rect(cornerRadius: 20))
    }
}
