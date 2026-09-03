import Contacts
import CoreLocation
import SwiftUI
import TouchTipsCore

/// The one write. Creates a real contact and an exact meeting where you are standing.
struct AddSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var name = ""
    @State private var phone = ""
    @State private var path: [Route] = []
    @State private var choices: [PlaceChoice] = []
    @State private var chosen: PlaceChoice?
    @State private var origin: CLLocationCoordinate2D?
    @State private var locating = true
    @State private var locationOff = false
    @State private var problem: String?
    @FocusState private var focus: Field?
    @Namespace private var chips

    private enum Field { case name, phone }
    private enum Route: Hashable { case elsewhere }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .phone }
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .focused($focus, equals: .phone)
                }

                Section("Where") {
                    whereRow
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                if let problem {
                    Section { Text(problem).foregroundStyle(.secondary) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .serifTitle("Just met")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        HapticManager.light()
                        dismiss()
                    } label: {
                        Icon("x")
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        HapticManager.medium()
                        save()
                    } label: {
                        Icon("check")
                    }
                    .disabled(trimmedName.isEmpty)
                    .accessibilityLabel("Save")
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .elsewhere:
                    PlacePicker(origin: origin) { picked in
                        choices.removeAll { $0.key == picked.key }
                        choices.insert(picked, at: 0)
                        chosen = picked
                    }
                }
            }
            .task {
                focus = .name
                await locate()
            }
        }
        // Full height, so the keyboard never covers Where.
        .presentationDetents([.large])
    }

    // MARK: - Where

    @ViewBuilder
    private var whereRow: some View {
        if locating {
            HStack(spacing: 12) {
                ProgressView()
                Text("Finding where you are").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
        } else if locationOff, choices.isEmpty {
            HStack(spacing: 12) {
                Text("Location is off").foregroundStyle(.secondary)
                Spacer()
                Button("Open Settings") {
                    HapticManager.light()
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal, 20)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(choices) { choice in
                                chip(choice.name, selected: chosen == choice, id: choice.key) {
                                    chosen = choice
                                }
                            }
                            chip("Elsewhere…", selected: false, id: "elsewhere") {
                                path.append(.elsewhere)
                            }
                            chip("No place", selected: chosen == nil, id: "none", dashed: true) {
                                chosen = nil
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .scrollClipDisabled()
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
        }
    }

    private var caption: String {
        if let chosen {
            return chosen.detail.map { "\(chosen.name) · \($0)" } ?? chosen.name
        }
        return "Saved with the time only."
    }

    private func chip(_ title: String, selected: Bool, id: String, dashed: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(selected ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .overlay {
                    if dashed, !selected {
                        Capsule().strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(.white).interactive() : .clear.interactive(), in: .capsule)
        .glassEffectID(id, in: chips)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Location

    private func locate() async {
        defer { locating = false }

        var list: [PlaceChoice] = []
        if let visit = app.capture.currentVisit,
           let place = try? await app.database.reader.read({ db in try Place.fetchOne(db, key: visit.placeID) })
        {
            origin = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            var title = place.name
            if title == nil {
                title = (try? await Geocoder.reverseGeocode(latitude: place.latitude, longitude: place.longitude))?.title
            }
            list.append(PlaceChoice(
                place: place,
                name: title ?? Format.coordinates(place.latitude, place.longitude),
                detail: "You are here · since \(Format.time(visit.start))"
            ))
        } else {
            guard let found = await liveLocation() else { return }
            origin = found
        }
        guard let origin else { return }

        let nearby = (try? await NearbyPlaces.around(origin)) ?? []
        for choice in nearby where !list.contains(where: { $0.key == choice.key }) && list.count < 5 {
            list.append(choice)
        }
        if list.isEmpty {
            let named = try? await Geocoder.reverseGeocode(latitude: origin.latitude, longitude: origin.longitude)
            list.append(PlaceChoice(
                key: PlaceKey.cell(latitude: origin.latitude, longitude: origin.longitude),
                name: named?.title ?? Format.coordinates(origin.latitude, origin.longitude),
                latitude: origin.latitude, longitude: origin.longitude,
                detail: named?.detail ?? "You are here"
            ))
        }
        choices = list
        chosen = list.first
    }

    private func liveLocation() async -> CLLocationCoordinate2D? {
        let status = app.capture.locationStatus
        guard status != .denied, status != .restricted else {
            locationOff = true
            return nil
        }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location { return location.coordinate }
                if update.authorizationDenied {
                    locationOff = true
                    return nil
                }
                if update.locationUnavailable { return nil }
            }
        } catch {
            Log.ui.notice("location for add failed: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - Save

    private func save() {
        let contact = CNMutableContact()
        let parts = trimmedName.split(separator: " ", maxSplits: 1)
        contact.givenName = parts.first.map(String.init) ?? ""
        contact.familyName = parts.count > 1 ? String(parts[1]) : ""
        let digits = phone.trimmingCharacters(in: .whitespaces)
        if !digits.isEmpty {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: digits))]
        }

        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        do {
            try CNContactStore().execute(request)
            var placeID: Int64?
            if let chosen {
                placeID = try app.database.writer.write { db in
                    try Place.findOrCreate(
                        db, key: chosen.key, latitude: chosen.latitude, longitude: chosen.longitude, name: chosen.name
                    ).id
                }
            }
            try Ingest.addExact(contactID: contact.identifier, name: trimmedName, at: .now, placeID: placeID, to: app.database)
            HapticManager.success()
            dismiss()
        } catch {
            HapticManager.error()
            problem = error.localizedDescription
        }
    }
}
