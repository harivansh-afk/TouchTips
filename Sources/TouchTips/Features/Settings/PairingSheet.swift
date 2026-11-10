// "Let Claude read your meetings?" The one moment the phone proves it owns the data.

import SwiftUI

struct PairingRequest: Identifiable, Hashable {
    let code: String
    var id: String { code }
}

struct PairingSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let code: String

    private enum Phase: Equatable {
        case loading, ready(String), working(String), connected(String), failed(String)
    }

    @State private var phase: Phase = .loading

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 0)
                switch phase {
                case .loading:
                    ProgressView("Checking code…")
                case let .ready(name), let .working(name):
                    Text("Let \(name) read your meetings?")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("\(name) will see names, meeting dates, places and your notes. Nothing else leaves your phone. You can disconnect it any time in Settings.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if case .working = phase {
                        ProgressView("Syncing and connecting…")
                    }
                case let .connected(name):
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    Text("\(name) is connected")
                        .font(.title2.weight(.semibold))
                    Text("Go back to \(name). It finishes on its own.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                case let .failed(message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text("Couldn't connect")
                        .font(.title2.weight(.semibold))
                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
                buttons
            }
            .padding(24)
            .background { Color.ground.ignoresSafeArea() }
            .serifTitle("Connect")
            .task { await load() }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var buttons: some View {
        switch phase {
        case let .ready(name):
            Button {
                HapticManager.medium()
                Task { await allow(name) }
            } label: {
                Text("Allow").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Don't Allow") {
                Task {
                    await app.cloud.deny(code: code)
                    dismiss()
                }
            }
            .foregroundStyle(.secondary)
        case .connected, .failed:
            Button {
                dismiss()
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .loading, .working:
            EmptyView()
        }
    }

    private func load() async {
        do {
            let info = try await app.cloud.pairingInfo(code: code)
            phase = .ready(info.clientName)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func allow(_ name: String) async {
        phase = .working(name)
        do {
            let connected = try await app.cloud.approve(code: code)
            HapticManager.success()
            phase = .connected(connected)
        } catch {
            HapticManager.warning()
            phase = .failed(error.localizedDescription)
        }
    }
}
