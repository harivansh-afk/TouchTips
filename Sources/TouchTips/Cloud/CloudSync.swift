// Keeps the cloud copy of the database current once the user has connected an AI client.
// Whole-snapshot pushes: debounced after any change to people, places or meetings.

import Foundation
import Observation
import TouchTipsCore
import UIKit

@MainActor
@Observable
final class CloudSync {
    private static let enabledKey = "cloudSyncEnabled"

    private let database: AppDatabase
    private(set) var isEnabled: Bool
    private(set) var clients: [PairedClient] = []
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?
    private(set) var isSyncing = false

    private var observation: Task<Void, Never>?
    private var pendingPush: Task<Void, Never>?

    init(database: AppDatabase) {
        self.database = database
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey) && DeviceKey.existing() != nil
    }

    func start() {
        guard isEnabled else { return }
        observe()
    }

    private var client: CloudClient? {
        DeviceKey.existing().map { CloudClient(baseURL: CloudClient.defaultBaseURL, deviceKey: $0) }
    }

    /// Turn sync on and push at once, so an AI client's first question already has data.
    func enable() async throws {
        let key = try DeviceKey.getOrCreate()
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        isEnabled = true
        try await push(with: CloudClient(baseURL: CloudClient.defaultBaseURL, deviceKey: key))
        observe()
    }

    /// What the app is being asked to allow.
    func pairingInfo(code: String) async throws -> PairingInfo {
        let key = try DeviceKey.getOrCreate()
        return try await CloudClient(baseURL: CloudClient.defaultBaseURL, deviceKey: key).pairingInfo(code: code)
    }

    /// The user tapped Allow. Returns the client's name.
    func approve(code: String) async throws -> String {
        if !isEnabled {
            try await enable()
        } else {
            await pushNow()
        }
        guard let client else { throw CloudError.keychain(errSecItemNotFound) }
        let name = try await client.approve(code: code)
        await refreshClients()
        return name
    }

    func deny(code: String) async {
        try? await client?.deny(code: code)
    }

    func refreshClients() async {
        guard let client else {
            clients = []
            return
        }
        do {
            clients = try await client.clients()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func revoke(_ paired: PairedClient) async {
        guard let client else { return }
        do {
            try await client.revoke(clientID: paired.id)
            clients.removeAll { $0.id == paired.id }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Delete the cloud copy and every connection, and stop syncing. The phone's own data stays.
    func deleteCloudData() async throws {
        if let client {
            try await client.deleteAccount()
        }
        observation?.cancel()
        observation = nil
        pendingPush?.cancel()
        DeviceKey.forget()
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        isEnabled = false
        clients = []
        lastSyncAt = nil
    }

    func pushNow() async {
        guard let client else { return }
        do {
            try await push(with: client)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func push(with client: CloudClient) async throws {
        isSyncing = true
        defer { isSyncing = false }
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "cloud-sync")
        defer {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
            }
        }
        let body = try await database.reader.read { db in try CloudSnapshot.build(db).encoded() }
        _ = try await client.pushSnapshot(body)
        lastSyncAt = Date()
        lastError = nil
    }

    /// Any committed change to people, places or meetings schedules a push two seconds later.
    private func observe() {
        guard observation == nil else { return }
        let tracked = ValueObservation.tracking { db in
            try (Person.fetchCount(db), Place.fetchCount(db), Meet.fetchCount(db))
        }
        let writer = database.writer
        observation = Task { [weak self] in
            do {
                for try await _ in tracked.values(in: writer) {
                    guard let self else { return }
                    schedulePush()
                }
            } catch {
                Log.ui.error("cloud observation ended: \(error.localizedDescription)")
            }
        }
    }

    private func schedulePush() {
        pendingPush?.cancel()
        pendingPush = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            await pushNow()
        }
    }
}
