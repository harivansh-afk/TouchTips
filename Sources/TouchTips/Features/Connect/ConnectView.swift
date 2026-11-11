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
                pill(url)

                HStack(spacing: 10) {
                    if client.sharesFirst {
                        share(prominent: true)
                        if let open = client.openURL {
                            openButton(open, prominent: false)
                        }
                    } else if let open = client.openURL {
                        openButton(open, prominent: true)
                        share(prominent: false)
                    } else {
                        share(prominent: true)
                    }
                }

                steps(client.steps)

                if client == .claude {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Claude Code").padding(.leading, 6)
                        pill(ConnectClient.claudeCodeCommand(url))
                        ShareLink(item: ConnectClient.claudeCodeCommand(url)) {
                            Text("Share command")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
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
        .serifTitle(client.name)
        .onAppear {
            UIPasteboard.general.string = url
            HapticManager.success()
        }
    }

    private func pill(_ text: String) -> some View {
        HStack(spacing: 12) {
            Text(text)
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
    }

    @ViewBuilder
    private func openButton(_ target: URL, prominent: Bool) -> some View {
        let label = Text("Open \(client.name)").frame(maxWidth: .infinity)
        if prominent {
            Button {
                HapticManager.light()
                openURL(target)
            } label: {
                label.foregroundStyle(.black)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .controlSize(.large)
        } else {
            Button {
                HapticManager.light()
                openURL(target)
            } label: {
                label
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func share(prominent: Bool) -> some View {
        let label = Text("Share").frame(maxWidth: .infinity)
        if prominent {
            ShareLink(item: url) {
                label.foregroundStyle(.black)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .controlSize(.large)
        } else {
            ShareLink(item: url) {
                label
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    private func steps(_ lines: [String]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, step in
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
    }
}
