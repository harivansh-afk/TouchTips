import SwiftUI
import TouchedTipsCore

struct PersonView: View {
    let contactID: String

    @Environment(AppModel.self) private var app
    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none
    @State private var row: PersonRow?
    @State private var evidence: Visit?
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
                    EvidenceList(row: row, visit: evidence)
                    MeetEditor(row: row)
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
                .padding(.bottom, 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
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
        let observation = ValueObservation.tracking { db -> (PersonRow?, Visit?) in
            let row = try Person.row(contactID: contactID).fetchOne(db)
            let visit = try row?.meet.flatMap(Visit.evidence(for:))?.fetchOne(db)
            return (row, visit)
        }
        do {
            for try await (row, visit) in observation.values(in: app.database.reader) {
                if self.row != row { self.row = row }
                if evidence != visit { evidence = visit }
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
                let detail = Format.placeAndWindow(row)
                if !detail.isEmpty {
                    if let placeID = row.place?.id {
                        Button {
                            HapticManager.selection()
                            router.showPlace(placeID)
                        } label: {
                            HStack(spacing: 6) {
                                Text(detail)
                                Icon(.mapTrifold, size: 14).opacity(0.7)
                            }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.press)
                        .padding(.top, 4)
                        .accessibilityHint("Shows this place on the map")
                    } else {
                        Text(detail).font(.callout).foregroundStyle(.secondary).padding(.top, 4)
                    }
                }
                Label {
                    Text(Format.tierName(meet.tier))
                } icon: {
                    ConfidenceDot(tier: meet.tier)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
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
}

private struct EvidenceList: View {
    let row: PersonRow
    let visit: Visit?

    var body: some View {
        if let meet = row.meet {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "How we know")
                ForEach(lines(for: meet), id: \.title) { line in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.title)
                            Text(line.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: line.symbol)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
        }
    }

    private struct Line {
        let symbol: String
        let title: String
        let detail: String
    }

    private func lines(for meet: Meet) -> [Line] {
        if meet.userSet {
            let fromApp = meet.precision == .exact && meet.addSeenStart == meet.start
            return [Line(
                symbol: fromApp ? "plus.circle" : "hand.point.up.left",
                title: fromApp ? "Added from TouchedTips" : "Set by you",
                detail: fromApp ? "Exact time and place." : "Your answer outranks everything else."
            )]
        }

        var lines: [Line] = []
        if let seenStart = meet.addSeenStart, let seenEnd = meet.addSeenEnd {
            lines.append(Line(
                symbol: "person.crop.circle.badge.plus",
                title: "Contact appeared",
                detail: "Between \(Format.time(seenStart)) and \(Format.time(seenEnd)), \(Format.longDate(seenEnd))."
            ))
        }
        switch (meet.tier, visit) {
        case (.witnessed, let visit?):
            lines.append(Line(symbol: "mappin.and.ellipse", title: "You were here", detail: Format.visitSpan(visit)))
        case (.inferred, let visit?):
            lines.append(Line(symbol: "mappin", title: "You were nearby", detail: "Closest visit, \(Format.visitSpan(visit))."))
        default:
            lines.append(Line(symbol: "mappin.slash", title: "No visit close to that time", detail: "Set the place if you remember it."))
        }
        return lines
    }
}
