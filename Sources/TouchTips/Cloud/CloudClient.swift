// The phone's half of the sync API. Every call carries the device key.

import Foundation

enum CloudError: LocalizedError {
    case keychain(OSStatus)
    case http(Int, String)
    case offline

    var errorDescription: String? {
        switch self {
        case let .keychain(status): "Couldn't store the sync key (\(status))."
        case let .http(status, message): message.isEmpty ? "The server answered \(status)." : message
        case .offline: "No connection."
        }
    }
}

/// One connected app. `url` is present only on the response that created it.
struct ConnectorKey: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var client: String
    var name: String
    var createdAt: String
    var lastUsedAt: String?
    var url: String?

    var kind: ConnectClient {
        ConnectClient(rawValue: client) ?? .other
    }
}

/// A client's sign-in, waiting for this phone's Allow.
struct ApprovalRequest: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var client: String
    /// "Claude", or "Some Name · host" when the sign-in doesn't return to that client's own site.
    var name: String
    var createdAt: String

    var kind: ConnectClient {
        ConnectClient(rawValue: client) ?? .other
    }

    /// The server only names a client it recognises. Anything else shows where it would send the user.
    var isRecognised: Bool {
        !name.contains(" · ")
    }
}

struct CloudClient: Sendable {
    var baseURL: URL
    var deviceKey: String

    static var defaultBaseURL: URL {
        #if DEBUG
            if let override = UserDefaults.standard.string(forKey: "cloudBaseURL"), let url = URL(string: override) {
                return url
            }
        #endif
        return URL(string: "https://touchtips.app")!
    }

    enum PushOutcome { case stored, alreadyNewer }

    func pushSnapshot(_ body: Data) async throws -> PushOutcome {
        let (status, _) = try await send("PUT", "/v1/snapshot", body: body)
        switch status {
        case 200: return .stored
        case 409: return .alreadyNewer
        default: throw CloudError.http(status, "Sync failed.")
        }
    }

    func createKey(client: ConnectClient) async throws -> ConnectorKey {
        let body = try JSONEncoder().encode(["client": client.rawValue])
        let (status, data) = try await send("POST", "/v1/keys", body: body)
        guard status == 201 else { throw CloudError.http(status, "Couldn't connect.") }
        return try JSONDecoder().decode(ConnectorKey.self, from: data)
    }

    /// The phone's MCP URL for a client that signs in with OAuth. Also lets that client's sign-in
    /// push an approval prompt to this phone for the next ten minutes.
    func startConnect(client: ConnectClient) async throws -> String {
        struct Body: Decodable { var url: String }
        let body = try JSONEncoder().encode(["client": client.rawValue])
        let (status, data) = try await send("POST", "/v1/connect", body: body)
        guard status == 200 else { throw CloudError.http(status, "Couldn't connect.") }
        return try JSONDecoder().decode(Body.self, from: data).url
    }

    /// Where approval prompts go. Debug builds get sandbox tokens; TestFlight and the App Store, production.
    func registerDevice(pushToken: String?, sandbox: Bool) async throws {
        var fields: [String: String] = ["apnsEnv": sandbox ? "sandbox" : "production"]
        fields["apnsToken"] = pushToken
        let (status, _) = try await send("PUT", "/v1/device", body: JSONEncoder().encode(fields))
        guard status == 200 else { throw CloudError.http(status, "Couldn't register for approvals.") }
    }

    func approvals() async throws -> [ApprovalRequest] {
        struct Body: Decodable { var requests: [ApprovalRequest] }
        let (status, data) = try await send("GET", "/v1/requests")
        guard status == 200 else { throw CloudError.http(status, "Couldn't load sign-in requests.") }
        return try JSONDecoder().decode(Body.self, from: data).requests
    }

    /// False when the request is gone: expired, or already answered.
    func decide(_ id: String, allow: Bool) async throws -> Bool {
        let (status, _) = try await send("POST", "/v1/requests/\(id)", body: JSONEncoder().encode(["allow": allow]))
        guard status == 200 || status == 404 else { throw CloudError.http(status, "Couldn't answer the request.") }
        return status == 200
    }

    func keys() async throws -> [ConnectorKey] {
        struct Body: Decodable { var keys: [ConnectorKey] }
        let (status, data) = try await send("GET", "/v1/keys")
        guard status == 200 else { throw CloudError.http(status, "Couldn't load connected apps.") }
        return try JSONDecoder().decode(Body.self, from: data).keys
    }

    func revoke(id: String) async throws {
        let (status, _) = try await send("DELETE", "/v1/keys/\(id)")
        guard status == 200 || status == 404 else { throw CloudError.http(status, "Couldn't disconnect.") }
    }

    func deleteAccount() async throws {
        let (status, _) = try await send("DELETE", "/v1/account")
        guard status == 204 else { throw CloudError.http(status, "Couldn't delete cloud data.") }
    }

    private func send(_ method: String, _ path: String, body: Data? = nil) async throws -> (Int, Data) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(deviceKey)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.timeoutInterval = 30
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw CloudError.offline
        }
    }
}
