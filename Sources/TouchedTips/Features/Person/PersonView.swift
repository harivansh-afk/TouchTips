import SwiftUI
import TouchedTipsCore

struct PersonView: View {
    let contactID: String

    @Environment(AppModel.self) private var app
    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none
    @State private var row: PersonRow?
    @State private var showCard = false

    var body: some View {
        ScrollView {
            if let row {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        ContactAvatar(contactID: row.id, initials: row.person.initials, size: 96)
                        Text(row.person.name)
                            .font(.display(36))
                            .multilineTextAlignment(.center)
                    }
                    MeetCard(row: row)
                        .smoothAppear()
                    MeetEditor(row: row)
                    NoteField(row: row)
                    Button {
                        HapticManager.medium()
                        showCard = true
                    } label: {
                        Text("Open in Contacts").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .aboveTabBar()
        .minimizesTabBarOnScroll()
        .background(Color.ground)
        // No bar at all: the push is the zoom and nothing else. Back is the tab bar's capsule, or the swipe.
        .toolbar(.hidden, for: .navigationBar)
        .navigationAllowDismissalGestures(allowDismissalGesture)
        .navigationBarBackButtonHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(1))
            allowDismissalGesture = .all
        }
        .sheet(isPresented: $showCard) {
            ContactCard(contactID: contactID).ignoresSafeArea()
        }
        .task { await observe() }
    }

    private func observe() async {
        let contactID = contactID
        let observation = ValueObservation.tracking { db in
            try Person.row(contactID: contactID).fetchOne(db)
        }
        do {
            for try await row in observation.values(in: app.database.reader) {
                if self.row != row { self.row = row }
            }
        } catch is CancellationError {
            // The view went away. Not an error.
        } catch {
            Log.ui.error("person observation ended: \(error.localizedDescription)")
        }
    }
}

private struct MeetCard: View {
    let row: PersonRow
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "First met")
            if let meet = row.meet {
                let headline = Format.headline(for: meet)
                Text(headline.lead).font(.display(32))
                Text(headline.body).font(.system(size: 30, weight: .bold)).kerning(-0.9)
                // Where, on its own line, marked with a pin.
                if let name = Format.placeName(row), let placeID = row.place?.id {
                    Button {
                        HapticManager.selection()
                        router.showPlace(placeID)
                    } label: {
                        placeLine(name)
                    }
                    .buttonStyle(.press)
                    .padding(.top, 6)
                    .accessibilityHint("Shows this place on the map")
                }
            } else {
                Text("Undocumented").font(.display(32))
                Text("Saved before the app was installed. Nothing to go on yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .glassEffect(.clear, in: .rect(cornerRadius: 22))
    }

    private func placeLine(_ name: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Icon(.mapPin, size: 16)
            Text(name)
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.primary)
    }
}
