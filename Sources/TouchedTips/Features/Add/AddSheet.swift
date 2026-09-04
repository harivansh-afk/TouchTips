import Contacts
import CoreLocation
import PhoneNumberKit
import SwiftUI
import TouchedTipsCore

/// The one write. Creates a real contact and an exact meeting where you are standing.
struct AddSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    /// Formats as you type for the device's region, and follows a typed country code instead.
    private let phoneFormatter = PartialFormatter()
    /// The region's own example number, written the way it will be formatted: "(201) 555-0123".
    private static let phonePrompt: String = {
        let utility = PhoneNumberUtility()
        guard let example = utility.getExampleNumber(forCountry: PhoneNumberUtility.defaultRegionCode()) else { return "Phone" }
        return utility.format(example, toType: .national)
    }()
    @State private var choices: [PlaceChoice] = []
    @State private var chosen: PlaceChoice?
    @State private var origin: CLLocationCoordinate2D?
    @State private var note: PlaceChooser.Note? = .locating
    @State private var problem: String?
    @FocusState private var focus: Field?

    private enum Field { case name, phone }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    fields
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Where").padding(.leading, 6)
                        PlaceChooser(candidates: choices, selection: $chosen, origin: origin, note: note)
                    }
                    if let problem {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            // Into the keyboard region too, or the translucent keyboard shows a hard edge where the black stops.
            .background { Color.ground.ignoresSafeArea() }
            .serifTitle("Just met")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        HapticManager.light()
                        dismiss()
                    } label: {
                        Icon(.x)
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        HapticManager.medium()
                        save()
                    } label: {
                        Icon(.check)
                    }
                    .disabled(trimmedName.isEmpty)
                    .accessibilityLabel("Save")
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

    // MARK: - Who

    /// Name and phone in one glass card, a hairline between them, like the card on the person screen.
    private var fields: some View {
        VStack(spacing: 0) {
            TextField("Name", text: $name)
                .textContentType(.name)
                .focused($focus, equals: .name)
                .submitLabel(.next)
                .onSubmit { focus = .phone }
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)
                .padding(.leading, 18)
            TextField(Self.phonePrompt, text: $phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .focused($focus, equals: .phone)
                .onChange(of: phone) { _, typed in
                    let formatted = phoneFormatter.formatPartial(typed)
                    if formatted != typed { phone = formatted }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
        }
        .glassEffect(.clear, in: .rect(cornerRadius: 22))
    }

    // MARK: - Location

    private func locate() async {
        defer { if note == .locating { note = nil } }

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
            note = .locationOff
            return nil
        }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location { return location.coordinate }
                if update.authorizationDenied {
                    note = .locationOff
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
        let typed = phone.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty {
            // Stored as +14345551234 when it parses, so Contacts and Phone treat it as a real number.
            let utility = PhoneNumberUtility()
            let stored = (try? utility.parse(typed)).map { utility.format($0, toType: .e164) } ?? typed
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: stored))]
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
