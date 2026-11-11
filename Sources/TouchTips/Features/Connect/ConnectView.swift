// Connect: tap a client, its URL is on the clipboard. Connected apps below. Nothing else.

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

    @State private var minted: ConnectorKey?
    @State private var working: ConnectClient?
    @State private var problem: String?
    @State private var disconnecting: ConnectorKey?
    @State private var confirmDelete = false

    private var connected: [ConnectorKey] {
        app.cloud.keys.filter { $0.lastUsedAt != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    card {
                        ForEach(Array(ConnectClient.allCases.enumerated()), id: \.element) { index, client in
                            if index > 0 {
                                hairline
                            }
                            clientRow(client)
                        }
                    }

                    if !connected.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(text: "Connected").padding(.leading, 6)
                            card {
                                ForEach(Array(connected.enumerated()), id: \.element.id) { index, key in
                                    if index > 0 {
                                        hairline
                                    }
                                    connectedRow(key)
                                }
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
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Text("Delete cloud data")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .tint(.red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background { Color.ground.ignoresSafeArea() }
            .serifTitle("Connect")
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
            .navigationDestination(item: $minted) { key in
                ConnectedView(key: key) { dismiss() }
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
                Text("Every connected app loses access. This phone keeps everything.")
            }
            .task {
                await app.cloud.refreshKeys()
                if let start, minted == nil {
                    await connect(start)
                }
            }
        }
    }

    // MARK: - Rows

    private func clientRow(_ client: ConnectClient) -> some View {
        Button {
            HapticManager.medium()
            Task { await connect(client) }
        } label: {
            HStack(spacing: 14) {
                Icon(client.icon, size: 22)
                    .foregroundStyle(.primary)
                Text(client.name)
                    .foregroundStyle(.primary)
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
            .padding(.vertical, 15)
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
            HStack(spacing: 14) {
                Icon(key.kind.icon, size: 22)
                    .foregroundStyle(.primary)
                Text(key.name)
                    .foregroundStyle(.primary)
                Spacer()
                Text("Disconnect")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
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

    private func card(@ViewBuilder rows: () -> some View) -> some View {
        VStack(spacing: 0) {
            rows()
        }
        .glassEffect(.clear, in: .rect(cornerRadius: 22))
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
            .padding(.leading, 54)
    }
}

/// The URL, already on the clipboard, and the way into the client.
struct ConnectedView: View {
    @Environment(\.openURL) private var openURL

    let key: ConnectorKey
    var onDone: () -> Void

    private var client: ConnectClient { key.kind }
    private var url: String { key.url ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 12) {
                    Text(url)
                        .font(.footnote.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Text("Copied")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                .glassEffect(.clear, in: .rect(cornerRadius: 22))

                HStack(spacing: 10) {
                    if let open = client.openURL {
                        Button {
                            HapticManager.light()
                            openURL(open)
                        } label: {
                            Text("Open \(client.name)")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    }
                    ShareLink(item: client.clipboardText(for: url)) {
                        Text("Share")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }

                VStack(spacing: 0) {
                    ForEach(Array(client.steps.enumerated()), id: \.offset) { index, step in
                        if index > 0 {
                            Rectangle().fill(Color.hairline).frame(height: 1).padding(.leading, 18)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.tertiary)
                            Text(step)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 15)
                    }
                }
                .glassEffect(.clear, in: .rect(cornerRadius: 22))

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
        .serifTitle(client.name)
        .onAppear {
            UIPasteboard.general.string = client.clipboardText(for: url)
            HapticManager.success()
        }
    }
}
