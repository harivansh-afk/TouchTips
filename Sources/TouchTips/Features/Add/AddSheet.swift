import Contacts
import PhoneNumberKit
import SwiftUI
import TouchTipsCore

/// The one write. Creates a real contact and an exact meeting, at a place you choose.
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
        guard let example = utility.getExampleNumber(forCountry: PhoneNumberUtility.defaultRegionCode())
        else { return "Phone" }
        return utility.format(example, toType: .national)
    }()

    @State private var choices: [PlaceChoice] = []
    @State private var place: PlaceChoice?
    @State private var problem: String?
    @State private var creation = ContactCreation()
    @FocusState private var focus: Field?

    private enum Field { case name, phone }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    fields
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Where").padding(.leading, 6)
                        PlaceChooser(candidates: choices, selection: $place, origin: choices.first?.coordinate)
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
                await loadRecent()
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
                    if formatted != typed {
                        phone = formatted
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
        }
        .glassEffect(.clear, in: .rect(cornerRadius: 22))
    }

    // MARK: - Where

    private func loadRecent() async {
        do {
            let recent = try await app.database.reader.read { db in try Place.recentlyMet(limit: 5).fetchAll(db) }
            choices = recent.map { PlaceChoice(place: $0, detail: nil) }
        } catch {
            Log.ui.error("recent places failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Save

    private func save() {
        do {
            let place = place.map {
                Place(key: $0.key, latitude: $0.latitude, longitude: $0.longitude, name: $0.name)
            }
            try creation.save(
                name: trimmedName, phone: phone, place: place, to: app.database
            )
            app.capture.scheduleTick(.user, after: 0)
            HapticManager.success()
            dismiss()
        } catch {
            HapticManager.error()
            problem = error.localizedDescription
        }
    }
}
