import SwiftUI
import TouchTipsCore

struct PersonView: View {
    let contactID: String

    @Environment(AppModel.self) private var app
    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none
    @State private var row: PersonRow?
    @State private var showCard = false
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var confirmationProblem: String?

    var body: some View {
        ScrollView {
            if let row {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        ContactAvatar(contactID: row.id, initials: row.person.initials, size: 96)
                        Text(row.person.name)
                            .accessibilityIdentifier("person-name")
                            .font(.display(36))
                            .multilineTextAlignment(.center)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        MeetCard(row: row)
                            .smoothAppear()
                        if row.meet?.isConfirmed == false {
                            Button("Confirm meeting") {
                                do {
                                    try Ingest.confirmMeet(contactID: row.id, now: .now, to: app.database)
                                    confirmationProblem = nil
                                    HapticManager.selection()
                                } catch {
                                    confirmationProblem = error.localizedDescription
                                    HapticManager.error()
                                }
                            }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("meeting.confirm")
                        }
                        if let confirmationProblem {
                            Text(confirmationProblem)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            } else if loadFailed {
                ContentUnavailableView(
                    "Couldn't load this contact",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Go back and try opening the contact again.")
                )
            } else if loaded {
                ContentUnavailableView(
                    "Contact unavailable",
                    systemImage: "person.crop.circle.badge.xmark",
                    description: Text("This contact was removed or is no longer available to TouchTips.")
                )
            } else {
                ProgressView("Loading contact")
                    .padding(.top, 40)
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
        .task(id: contactID) { await observe() }
    }

    private func observe() async {
        row = nil
        loaded = false
        loadFailed = false
        let contactID = contactID
        let observation = ValueObservation.tracking { db in
            try Person.row(contactID: contactID).fetchOne(db)
        }
        do {
            for try await row in observation.values(in: app.database.reader) {
                if self.row != row {
                    self.row = row
                }
                loaded = true
            }
        } catch is CancellationError {
            // The view went away. Not an error.
        } catch {
            loadFailed = true
            Log.ui.error("person observation ended: \(error.localizedDescription)")
        }
    }
}

private struct MeetCard: View {
    let row: PersonRow
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: row.meet?.isConfirmed == false ? "Suggested meeting" : "First met")
            if let meet = row.meet {
                HStack(spacing: 8) {
                    ConfidenceDot(meet: meet)
                    Text(meet.isConfirmed ? "Confirmed" : "Not yet confirmed")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
                Text("No meeting details").font(.display(32))
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
