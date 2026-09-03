import SwiftUI
import TouchedTipsCore
import UniformTypeIdentifiers

struct SettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var showImporter = false
    @State private var importing = false
    @State private var importSummary: TimelineImporter.Summary?
    @State private var problem: String?
    @State private var named = 0
    @State private var total = 0
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Access") {
                    LabeledContent("Contacts") {
                        if app.contactsAccess.granted {
                            Text("Full")
                        } else {
                            Button("Allow") {
                                Task {
                                    await app.contactsAccess.request()
                                    app.capture.scheduleTick()
                                }
                            }
                        }
                    }
                    LabeledContent("Location") {
                        if app.capture.locationGranted {
                            Text("Always")
                        } else if app.capture.locationStatus == .denied || app.capture.locationStatus == .restricted {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        } else {
                            Button("Allow") { app.capture.requestLocation() }
                        }
                    }
                }

                Section {
                    Button(importing ? "Importing…" : "Import Google Timeline") { showImporter = true }
                        .disabled(importing)
                    if let importSummary {
                        Text(summaryText(importSummary)).foregroundStyle(.secondary)
                    }
                    if let problem {
                        Text(problem).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("History")
                } footer: {
                    Text("In Google Maps: your avatar, Settings, Location & Privacy, Export Timeline data. Save to Files, then pick it here. Re-importing is safe.")
                }

                Section("Places") {
                    LabeledContent("Named", value: "\(named) of \(total)")
                }

                Section {
                    Button("Delete all data", role: .destructive) { confirmDelete = true }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ground)
            .serifTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        HapticManager.light()
                        dismiss()
                    } label: {
                        Icon(.check)
                    }
                    .accessibilityLabel("Done")
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                Task { await importFile(result) }
            }
            .confirmationDialog("Delete everything TouchedTips knows?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all data", role: .destructive) {
                    HapticManager.warning()
                    deleteAll()
                }
            } message: {
                Text("Contacts themselves are untouched. Meetings, visits and imports are removed.")
            }
            .onAppear { app.contactsAccess.refresh() }
            .task { await observeCounts() }
        }
    }

    private func summaryText(_ summary: TimelineImporter.Summary) -> String {
        guard summary.visitsAdded > 0, let first = summary.first, let last = summary.last else {
            return "Nothing new in that file."
        }
        return "Added \(summary.visitsAdded) visits at \(summary.placesAdded) new places, \(Format.yearSpan(first, last))."
    }

    private func importFile(_ result: Result<URL, any Error>) async {
        importing = true
        defer { importing = false }
        problem = nil

        let database = app.database
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)

            importSummary = try await Task.detached(priority: .userInitiated) {
                let segments = try TimelineExport.decode(data)
                let summary = try TimelineImporter.importVisits(segments, into: database)
                try Ingest.reresolveAll(now: .now, to: database)
                return summary
            }.value
            app.geocoder.kick()
            HapticManager.success()
        } catch {
            HapticManager.error()
            problem = error.localizedDescription
        }
    }

    private func deleteAll() {
        do {
            try Ingest.deleteAll(app.database)
            importSummary = nil
            app.capture.scheduleTick()
        } catch {
            HapticManager.error()
            problem = error.localizedDescription
        }
    }

    private func observeCounts() async {
        let observation = ValueObservation.tracking { db -> (Int, Int) in
            let placed = Place.withMeets()
            return (try placed.filter(Place.Columns.name != nil).fetchCount(db), try placed.fetchCount(db))
        }
        do {
            for try await (named, total) in observation.values(in: app.database.reader) {
                if self.named != named { self.named = named }
                if self.total != total { self.total = total }
            }
        } catch is CancellationError {
            // The view went away. Not an error.
        } catch {
            Log.ui.error("count observation ended: \(error.localizedDescription)")
        }
    }
}
