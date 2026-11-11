// Keeps the cloud copy of the database current once any client is connected, and answers
// clients' sign-ins: the server asks this phone, and only Allow here lets a client read anything.
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
    private(set) var keys: [ConnectorKey] = []
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?
    private(set) var isSyncing = false
    /// A sign-in waiting for Allow or Don't Allow on screen.
    var pendingApproval: ApprovalRequest?
    /// The Connect sheet is up, so it shows the Allow sheet instead of the root.
    var connectScreenOpen = false

    private var observation: Task<Void, Never>?
    private var pendingPush: Task<Void, Never>?

    init(database: AppDatabase) {
        self.database = database
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey) && DeviceKey.existing() != nil
    }

    func start() {
        guard isEnabled else { return }
        observe()
        // Every launch: the server stores only sealed data, so a phone that synced before it did pushes again.
        Task {
            await pushNow()
            await registerDevice()
        }
    }

    private var api: CloudClient? {
        DeviceKey.existing().map { CloudClient(baseURL: CloudClient.defaultBaseURL, deviceKey: $0) }
    }

    /// Start a connection. The first one turns sync on and pushes, so the client's first question has data.
    /// OAuth clients get this phone's MCP URL, which is not a secret: the client signs in and the phone approves.
    /// The rest get a connector URL. Tapping one again before its URL was used hands back the same URL.
    func connect(_ client: ConnectClient) async throws -> ConnectorKey {
        if isEnabled {
            await pushNow()
        } else {
            try await enable()
        }
        guard let api else { throw CloudError.keychain(errSecItemNotFound) }
        if client.usesOAuth {
            await registerDevice()
            let url = try await api.startConnect(client: client)
            return ConnectorKey(id: "oauth-\(client.rawValue)", client: client.rawValue, name: client.name, createdAt: "", url: url)
        }
        if var pending = keys.first(where: { $0.kind == client && $0.lastUsedAt == nil }),
           let url = Self.urls[pending.id] {
            pending.url = url
            return pending
        }
        let key = try await api.createKey(client: client)
        keys.removeAll { $0.kind == client && $0.lastUsedAt == nil }
        keys.insert(key, at: 0)
        if let url = key.url {
            Self.urls[key.id] = url
        }
        return key
    }

    /// URLs this phone minted, by key id. The server never returns them again.
    private static var urls: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "connectorURLs") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "connectorURLs") }
    }

    // MARK: - Approvals

    private static let pushTokenKey = "apnsToken"

    /// From the app delegate, whenever iOS hands over a device token.
    static func storePushToken(_ token: Data) {
        UserDefaults.standard.set(token.map { String(format: "%02x", $0) }.joined(), forKey: pushTokenKey)
    }

    /// Tell the server where to send approval prompts. Harmless to repeat.
    func registerDevice() async {
        guard isEnabled, let api else { return }
        #if DEBUG
            let sandbox = true
        #else
            let sandbox = false
        #endif
        do {
            try await api.registerDevice(pushToken: UserDefaults.standard.string(forKey: Self.pushTokenKey), sandbox: sandbox)
        } catch {
            Log.ui.error("device registration failed: \(error.localizedDescription)")
        }
    }

    /// Anything waiting goes on screen. Called when the app comes forward and when a prompt is tapped.
    func checkApprovals(showing id: String? = nil) async {
        guard isEnabled, let api else { return }
        guard let requests = try? await api.approvals() else { return }
        let next = id.flatMap { id in requests.first { $0.id == id } } ?? requests.first
        if let next, pendingApproval?.id != next.id {
            pendingApproval = next
        }
    }

    /// Allow or Don't Allow, from the sheet or straight from the notification.
    func decide(_ id: String, allow: Bool) async {
        guard let api else { return }
        do {
            _ = try await api.decide(id, allow: allow)
            if pendingApproval?.id == id {
                pendingApproval = nil
            }
            if allow {
                HapticManager.success()
            }
            // The client exchanges its code a moment later; the list picks it up then.
            try? await Task.sleep(for: .seconds(3))
            await refreshKeys()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshKeys() async {
        guard let api else {
            keys = []
            return
        }
        do {
            keys = try await api.keys()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func revoke(_ key: ConnectorKey) async {
        guard let api else { return }
        do {
            try await api.revoke(id: key.id)
            keys.removeAll { $0.id == key.id }
            Self.urls[key.id] = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Delete the cloud copy and every connection, and stop syncing. The phone's own data stays.
    func deleteCloudData() async throws {
        if let api {
            try await api.deleteAccount()
        }
        observation?.cancel()
        observation = nil
        pendingPush?.cancel()
        DeviceKey.forget()
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        isEnabled = false
        keys = []
        lastSyncAt = nil
        UserDefaults.standard.removeObject(forKey: "connectorURLs")
    }

    func pushNow() async {
        guard let api else { return }
        do {
            try await push(with: api)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func enable() async throws {
        let deviceKey = try DeviceKey.getOrCreate()
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        isEnabled = true
        try await push(with: CloudClient(baseURL: CloudClient.defaultBaseURL, deviceKey: deviceKey))
        observe()
        await registerDevice()
    }

    private func push(with api: CloudClient) async throws {
        isSyncing = true
        defer { isSyncing = false }
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "cloud-sync")
        defer {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
            }
        }
        let body = try await database.reader.read { db in try CloudSnapshot.build(db).encoded() }
        _ = try await api.pushSnapshot(body)
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
