// The phone's half of the sync and pairing API. Every call carries the device key.

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

struct PairedClient: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var pairedAt: String
}

struct PairingInfo: Decodable, Sendable {
    var clientName: String
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

    func pairingInfo(code: String) async throws -> PairingInfo {
        let (status, data) = try await send("GET", "/v1/pair/\(code)")
        guard status == 200 else { throw CloudError.http(status, "That code isn't valid any more.") }
        return try JSONDecoder().decode(PairingInfo.self, from: data)
    }

    func approve(code: String) async throws -> String {
        let (status, data) = try await send("POST", "/v1/pair/\(code)/approve")
        guard status == 200 else { throw CloudError.http(status, "That code isn't valid any more.") }
        return try JSONDecoder().decode(PairingInfo.self, from: data).clientName
    }

    func deny(code: String) async throws {
        _ = try await send("POST", "/v1/pair/\(code)/deny")
    }

    func clients() async throws -> [PairedClient] {
        struct Body: Decodable { var clients: [PairedClient] }
        let (status, data) = try await send("GET", "/v1/clients")
        guard status == 200 else { throw CloudError.http(status, "Couldn't load connected apps.") }
        return try JSONDecoder().decode(Body.self, from: data).clients
    }

    func revoke(clientID: String) async throws {
        let encoded = clientID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? clientID
        let (status, _) = try await send("DELETE", "/v1/clients/\(encoded)")
        guard status == 200 else { throw CloudError.http(status, "Couldn't disconnect.") }
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
