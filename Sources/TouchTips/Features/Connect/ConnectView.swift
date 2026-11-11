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

/// One numbered list: the link (already on the clipboard), the way into the client, then what to tap there.
struct ConnectedView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 26

    let key: ConnectorKey
    var onDone: () -> Void

    @State private var web: WebDestination?
    @State private var copied: String?

    private var client: ConnectClient { key.kind }
    private var url: String { key.url ?? "" }

    var body: some View {
        let way = client.way(for: url)
        let clipboard = client.clipboardText(for: url)
        let first = way == nil ? 2 : 3
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 0) {
                        step(.done, client.copiedTitle) {
                            field(clipboard)
                        }
                        if let way {
                            hairline
                            if typeSize.isAccessibilitySize {
                                step(.number(2), client.openTitle, detail: client.openDetail) {
                                    openButton(way)
                                }
                            } else {
                                step(.number(2), client.openTitle, detail: client.openDetail) {
                                    EmptyView()
                                } trailing: {
                                    openButton(way)
                                }
                            }
                        }
                        ForEach(Array(client.finish.enumerated()), id: \.offset) { index, line in
                            hairline
                            step(.number(first + index), line) { EmptyView() }
                        }
                    }
                    .glassEffect(.clear, in: .rect(cornerRadius: 22))

                    if let note = client.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                    }
                }

                if client == .claude {
                    let command = ConnectClient.claudeCodeCommand(url)
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Or in Claude Code").padding(.leading, 6)
                        field(command)
                        Text(copied == command ? "Copied. Run it in your terminal." : "Tap to copy.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
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
        .sheet(item: $web) { destination in
            SafariView(url: destination.url)
                .ignoresSafeArea()
        }
        .onAppear {
            UIPasteboard.general.string = clipboard
            copied = clipboard
            HapticManager.success()
        }
    }

    // MARK: - Steps

    private enum Badge {
        case done
        case number(Int)
    }

    private func step(
        _ badge: Badge,
        _ title: String,
        detail: String? = nil,
        @ViewBuilder below: () -> some View,
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                badgeView(badge)
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Self.markdown(title))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    below()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func badgeView(_ badge: Badge) -> some View {
        ZStack {
            Circle().fill(Color.pill)
            switch badge {
            case .done:
                Icon(.check, size: badgeSize / 2)
            case let .number(value):
                Text("\(value)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
        }
        .foregroundStyle(.primary)
        .frame(width: badgeSize, height: badgeSize)
        .accessibilityHidden(true)
    }

    /// Text that copies on tap, with Share beside it.
    private func field(_ text: String) -> some View {
        HStack(spacing: 4) {
            Button {
                UIPasteboard.general.string = text
                copied = text
                HapticManager.light()
            } label: {
                Text(text)
                    .font(.footnote.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
                    .padding(.vertical, 10)
                    .contentShape(.rect)
            }
            .buttonStyle(.press)
            .accessibilityLabel("Copy")
            .accessibilityValue(text)

            ShareLink(item: text) {
                Icon(.export, size: 18)
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
            }
            .tint(.primary)
            .accessibilityLabel("Share")
        }
        .background(Color.hairline, in: .rect(cornerRadius: 12))
    }

    private func openButton(_ way: ConnectClient.Way) -> some View {
        Button {
            HapticManager.light()
            switch way {
            case let .app(target): openURL(target)
            case let .web(target): web = WebDestination(url: target)
            }
        } label: {
            Text("Open")
                .font(.body.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(.white)
        .controlSize(.regular)
        .accessibilityLabel(client.openTitle)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
            .padding(.leading, 16 + badgeSize + 14)
    }

    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
