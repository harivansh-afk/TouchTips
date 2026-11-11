// Connect: pick a client, get its URL. Every connected app listed under it. Nothing else.

import SwiftUI

struct ConnectRequest: Identifiable, Hashable {
    /// Nil opens the screen without starting a connection.
    var client: ConnectClient?
    var id: String { client?.id ?? "connect" }
}

struct ConnectView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// A client to connect the moment the screen appears, from a touchtips.app/connect/<client> link.
    var start: ConnectClient?
    /// Presented as a sheet (own stack, Done button) or pushed from Settings.
    var isSheet = true

    @State private var minted: ConnectorKey?
    @State private var working: ConnectClient?
    @State private var problem: String?
    @State private var disconnecting: ConnectorKey?
    @State private var confirmDelete = false

    var body: some View {
        if isSheet {
            NavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                group("Connect", footer: "Each client gets its own private URL. Paste it once; no login, no codes.") {
                    ForEach(Array(ConnectClient.allCases.enumerated()), id: \.element) { index, client in
                        if index > 0 {
                            hairline
                        }
                        clientRow(client)
                    }
                }

                if !app.cloud.keys.isEmpty {
                    group("Connected", footer: "Tap one to disconnect it. Its URL stops working at once.") {
                        ForEach(Array(app.cloud.keys.enumerated()), id: \.element.id) { index, key in
                            if index > 0 {
                                hairline
                            }
                            connectedRow(key)
                        }
                    }
                }

                if let problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }

                if app.cloud.isEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Text("Delete cloud data")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .tint(.red)
                        Text("Removes the cloud copy and disconnects every app. Your phone keeps everything.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background { Color.ground.ignoresSafeArea() }
        .serifTitle("Connect")
        .toolbar {
            if isSheet {
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
        }
        .navigationDestination(item: $minted) { key in
            ConnectedView(key: key) {
                if isSheet {
                    dismiss()
                } else {
                    minted = nil
                }
            }
        }
        .confirmationDialog(
            "Disconnect \(disconnecting?.name ?? "")?",
            isPresented: Binding(get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                if let key = disconnecting {
                    HapticManager.warning()
                    Task { await app.cloud.revoke(key) }
                }
            }
        } message: {
            Text("Its URL stops working at once.")
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
        .task {
            await app.cloud.refreshKeys()
            if let start, minted == nil {
                await connect(start)
            }
        }
    }

    // MARK: - Rows

    private func clientRow(_ client: ConnectClient) -> some View {
        Button {
            HapticManager.medium()
            Task { await connect(client) }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.name)
                        .foregroundStyle(.primary)
                    Text(client.tagline)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if working == client {
                    ProgressView()
                } else {
                    Icon(.caretRight, size: 14)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.press)
        .disabled(working != nil)
        .accessibilityIdentifier("connect-\(client.id)")
    }

    private func connectedRow(_ key: ConnectorKey) -> some View {
        Button {
            disconnecting = key
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.name)
                        .foregroundStyle(.primary)
                    Text(Self.lastUsed(key.lastUsedAt))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Disconnect")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.press)
    }

    private func connect(_ client: ConnectClient) async {
        working = client
        defer { working = nil }
        do {
            minted = try await app.cloud.connect(client)
            problem = nil
        } catch {
            HapticManager.warning()
            problem = error.localizedDescription
        }
    }

    // MARK: - Pieces

    private func group(_ title: String, footer: String? = nil, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: title).padding(.leading, 6)
            VStack(spacing: 0) {
                rows()
            }
            .glassEffect(.clear, in: .rect(cornerRadius: 22))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
            .padding(.leading, 18)
    }

    private static let isoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso = ISO8601DateFormatter()

    static func lastUsed(_ value: String?) -> String {
        guard let value, let date = isoFraction.date(from: value) ?? iso.date(from: value) else { return "Not used yet" }
        return "Used " + date.formatted(.relative(presentation: .named))
    }
}

/// The URL, already on the clipboard, and what to do with it.
struct ConnectedView: View {
    let key: ConnectorKey
    var onDone: () -> Void

    private var client: ConnectClient { key.kind }
    private var url: String { key.url ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Your private URL").padding(.leading, 6)
                    Text(url)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 15)
                        .glassEffect(.clear, in: .rect(cornerRadius: 22))
                    HStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = client.clipboardText(for: url)
                            HapticManager.success()
                        } label: {
                            Text(copyLabel)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        ShareLink(item: client.clipboardText(for: url)) {
                            Text("Share")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                    Text("\(client.clipboardLabel). Anyone with this URL can read your meetings; disconnect it any time from Connect.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Then, in \(client.name)").padding(.leading, 6)
                    VStack(spacing: 0) {
                        ForEach(Array(client.steps.enumerated()), id: \.offset) { index, step in
                            if index > 0 {
                                Rectangle().fill(Color.hairline).frame(height: 1).padding(.leading, 18)
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 16, alignment: .trailing)
                                Text(step)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 13)
                        }
                    }
                    .glassEffect(.clear, in: .rect(cornerRadius: 22))
                }

                Button {
                    HapticManager.light()
                    onDone()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background { Color.ground.ignoresSafeArea() }
        .serifTitle("\(client.name) connected")
        .onAppear {
            UIPasteboard.general.string = client.clipboardText(for: url)
            HapticManager.success()
        }
    }

    private var copyLabel: String {
        switch client {
        case .claudeCode: "Copy command"
        case .cursor, .vscode: "Copy install link"
        default: "Copy URL"
        }
    }
}
