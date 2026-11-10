// Settings › Connected apps: type a code, see who is connected, disconnect, or wipe the cloud copy.

import SwiftUI

struct ConnectedAppsView: View {
    @Environment(AppModel.self) private var app
    @State private var code = ""
    @State private var pairing: PairingRequest?
    @State private var confirmDelete = false
    @State private var problem: String?

    private static let connectorURL = "https://touchtips.app/mcp"

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("6-digit code", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.title3.monospacedDigit())
                        .onChange(of: code) { _, value in
                            code = String(value.filter(\.isNumber).prefix(6))
                        }
                    Button("Connect") {
                        HapticManager.light()
                        pairing = PairingRequest(code: code)
                    }
                    .disabled(code.count != 6)
                }
            } header: {
                Text("Enter a code")
            } footer: {
                Text("Add the connector URL to Claude, ChatGPT or Claude Code. It shows a code; enter it here. On this phone, tapping Open TouchTips on that page does it for you.")
            }

            Section {
                HStack {
                    Text(Self.connectorURL)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = Self.connectorURL
                        HapticManager.light()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Copy connector URL")
                }
                Link("How to connect each app", destination: URL(string: "https://touchtips.app/connect")!)
            } header: {
                Text("Connector URL")
            }

            Section {
                if app.cloud.clients.isEmpty {
                    Text(app.cloud.isEnabled ? "No apps connected." : "Nothing is shared until you connect an app.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(app.cloud.clients) { client in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(client.name)
                            Text("Connected \(Self.display(client.pairedAt))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await app.cloud.revoke(client) }
                            } label: {
                                Label("Disconnect", systemImage: "xmark")
                            }
                        }
                    }
                }
            } header: {
                Text("Connected apps")
            } footer: {
                Text("Connected apps see names, meeting dates, places and your notes. No phone numbers or emails. Swipe to disconnect.")
            }

            if app.cloud.isEnabled {
                Section {
                    LabeledContent("Last sync", value: app.cloud.lastSyncAt.map(Self.display) ?? "Not yet")
                    Button("Sync now") {
                        Task { await app.cloud.pushNow() }
                    }
                    .disabled(app.cloud.isSyncing)
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Text("Delete cloud data")
                    }
                } footer: {
                    if let problem = problem ?? app.cloud.lastError {
                        Text(problem).foregroundStyle(.secondary)
                    } else {
                        Text("Deleting removes the cloud copy and disconnects every app. Your phone keeps everything.")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { Color.ground.ignoresSafeArea() }
        .serifTitle("Connected apps")
        .sheet(item: $pairing) { request in
            PairingSheet(code: request.code)
                .environment(app)
                .onDisappear {
                    code = ""
                    Task { await app.cloud.refreshClients() }
                }
        }
        .alert("Delete cloud data?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                HapticManager.warning()
                Task {
                    do {
                        try await app.cloud.deleteCloudData()
                        problem = nil
                    } catch {
                        problem = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Every connected app loses access. TouchTips on this phone is unaffected.")
        }
        .task { await app.cloud.refreshClients() }
    }

    private static func display(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) ?? isoWithFraction.date(from: iso) else { return iso }
        return display(date)
    }

    private static func display(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
