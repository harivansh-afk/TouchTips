import Contacts
import CoreLocation
import SwiftUI
import TouchTipsCore

/// The one write. Creates a real contact and an exact meeting where you are standing.
struct AddSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    @State private var here: Here?
    @State private var locating = true
    @State private var attachPlace = true
    @State private var problem: String?
    @FocusState private var focus: Field?

    private enum Field { case name, phone }

    private struct Here {
        var name: String
        var latitude: Double
        var longitude: Double
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
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
                    if let here {
                        Toggle(isOn: $attachPlace) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(here.name)
                                Text("You are here").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    } else if locating {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Finding where you are").foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No location right now").foregroundStyle(.secondary)
                    }
                }

                if let problem {
                    Section { Text(problem).foregroundStyle(.secondary) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Just met")
            .navigationBarTitleDisplayMode(.inline)
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
            .task {
                focus = .name
                await locate()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func locate() async {
        defer { locating = false }

        if let visit = app.capture.currentVisit,
           let place = try? await app.database.reader.read({ db in try Place.fetchOne(db, key: visit.placeID) })
        {
            var title = place.name
            if title == nil {
                title = (try? await Geocoder.reverseGeocode(latitude: place.latitude, longitude: place.longitude))?.title
            }
            here = Here(
                name: title ?? Format.coordinates(place.latitude, place.longitude),
                latitude: place.latitude, longitude: place.longitude
            )
            return
        }

        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location {
                    let coordinate = location.coordinate
                    let named = try? await Geocoder.reverseGeocode(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    let title = named?.title ?? Format.coordinates(coordinate.latitude, coordinate.longitude)
                    here = Here(name: title, latitude: coordinate.latitude, longitude: coordinate.longitude)
                    return
                }
                if update.authorizationDenied || update.locationUnavailable { return }
            }
        } catch {
            Log.ui.notice("location for add failed: \(error.localizedDescription)")
        }
    }

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
            if attachPlace, let here {
                placeID = try app.database.writer.write { db in
                    try Place.findOrCreate(
                        db, key: PlaceKey.cell(latitude: here.latitude, longitude: here.longitude),
                        latitude: here.latitude, longitude: here.longitude, name: here.name
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
