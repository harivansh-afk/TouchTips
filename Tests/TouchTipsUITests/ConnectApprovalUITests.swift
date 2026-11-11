import CryptoKit
import XCTest

/// End to end against a running server. The app is the phone; this test is the MCP client, doing what Claude does:
/// discovery, registration, authorize with PKCE, waiting on the page, token exchange, then reading through MCP.
/// The approval prompt is a real APNs push (sandbox), so the server needs its APNs key.
///
/// Skipped unless the runner gets a server:
///   TEST_RUNNER_TOUCHTIPS_CLOUD_E2E=http://127.0.0.1:5199 xcodebuild test -only-testing:TouchTipsUITests/ConnectApprovalUITests …
@MainActor
final class ConnectApprovalUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var base: String {
        ProcessInfo.processInfo.environment["TOUCHTIPS_CLOUD_E2E"] ?? ""
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["TOUCHTIPS_CLOUD_E2E"] != nil else {
            throw XCTSkip("Set TOUCHTIPS_CLOUD_E2E to a running server to run this test")
        }
    }

    func testClientSignsInAndThePhoneAllows() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES", "-cloudBaseURL", base]
        app.launchEnvironment["TOUCHTIPS_QA_SESSION"] = UUID().uuidString
        app.launchEnvironment["TOUCHTIPS_QA_DATA"] = "standard"
        app.launch()
        allowNotifications(app)

        // The user taps Claude in Connect. The screen shows this phone's MCP URL.
        app.buttons["Connect"].tap()
        let claude = app.buttons["connect-claude"]
        XCTAssertTrue(claude.waitForExistence(timeout: 10))
        claude.tap()
        let field = app.buttons["Copy"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), app.debugDescription)
        let mcpURL = try XCTUnwrap(field.value as? String)
        XCTAssertTrue(mcpURL.hasSuffix("/mcp") && mcpURL.contains("/u/"), mcpURL)

        // Claude: discovery and registration.
        let client = try await MCPClient(mcpURL: mcpURL)

        // Sign-in while TouchTips is open: the push becomes the Allow sheet.
        var attempt = try await client.authorize()
        let number = app.buttons["approval.number.\(attempt.number)"]
        XCTAssertTrue(number.waitForExistence(timeout: 30), "no Allow sheet: \(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["Allow Claude?"].exists)
        number.tap()
        var tokens = try await client.finish(attempt)
        let found = try await client.searchPeople("QA Alice", token: tokens.accessToken)
        XCTAssertTrue(found.contains("QA Alice"), found)

        // Sign-in while TouchTips is in the background: the notification opens the number picker.
        // Allowing closed the window, so the user starts this one from the app again, as they would.
        app.buttons["Done"].firstMatch.tap()
        app.buttons["Connect"].tap()
        XCTAssertTrue(claude.waitForExistence(timeout: 10))
        claude.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.activate()
        try await Task.sleep(for: .seconds(2))
        attempt = try await client.authorize()
        let notice = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Allow Claude?")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 20), springboard.debugDescription)
        notice.tap()
        let second = app.buttons["approval.number.\(attempt.number)"]
        XCTAssertTrue(second.waitForExistence(timeout: 15), app.debugDescription)
        second.tap()
        tokens = try await client.finish(attempt)
        let bob = try await client.searchPeople("QA Bob", token: tokens.accessToken)
        XCTAssertTrue(bob.contains("QA Bob"), bob)

        // A wrong number allows nothing, and Don't Allow sends the client away with nothing.
        app.buttons["Done"].firstMatch.tap()
        app.buttons["Connect"].tap()
        XCTAssertTrue(claude.waitForExistence(timeout: 10))
        claude.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        attempt = try await client.authorize()
        let decoy = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'approval.number.' AND identifier != %@", "approval.number.\(attempt.number)")).firstMatch
        XCTAssertTrue(decoy.waitForExistence(timeout: 30))
        decoy.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        app.buttons["Close"].tap()
        let refused = try await client.waitForRedirect(attempt)
        XCTAssertEqual(URLComponents(string: refused)?.queryItems?.first { $0.name == "error" }?.value, "access_denied")
        attempt = try await client.authorize()
        let deny = app.buttons["approval.deny"]
        XCTAssertTrue(deny.waitForExistence(timeout: 30))
        deny.tap()
        let location = try await client.waitForRedirect(attempt)
        XCTAssertEqual(URLComponents(string: location)?.queryItems?.first { $0.name == "error" }?.value, "access_denied")
    }

    private func allowNotifications(_ app: XCUIApplication) {
        app.buttons["Settings"].tap()
        let row = app.buttons["settings-access-notifications"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        if row.label.contains("Allow") {
            row.tap()
            let allow = springboard.alerts.buttons["Allow"]
            if allow.waitForExistence(timeout: 5) {
                allow.tap()
            }
        }
        app.buttons["Done"].firstMatch.tap()
    }
}

/// Just enough of an MCP client: what Claude does with a server URL.
private struct MCPClient {
    struct Attempt {
        var request: String
        var secret: String
        var number: Int
        var verifier: String
        var pollURL: URL
    }

    struct Tokens {
        var accessToken: String
    }

    let mcpURL: URL
    let authorizeURL: URL
    let tokenURL: URL
    let clientID: String
    let redirect = "https://claude.ai/api/mcp/auth_callback"

    init(mcpURL string: String) async throws {
        mcpURL = try XCTUnwrap(URL(string: string))
        var probe = URLRequest(url: mcpURL)
        probe.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: probe)
        let challenge = try XCTUnwrap((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "www-authenticate"))
        let metadataURL = try XCTUnwrap(challenge.firstMatch(of: /resource_metadata="([^"]+)"/).map { String($0.1) })
        let resource = try await Self.json(URL(string: metadataURL)!)
        let issuer = try XCTUnwrap(URL(string: try XCTUnwrap((resource["authorization_servers"] as? [String])?.first)))
        // RFC 8414: the well-known segment goes between the host and the issuer's path.
        var metadata = try XCTUnwrap(URLComponents(url: issuer, resolvingAgainstBaseURL: false))
        metadata.path = "/.well-known/oauth-authorization-server" + issuer.path
        let server = try await Self.json(try XCTUnwrap(metadata.url))
        authorizeURL = URL(string: server["authorization_endpoint"] as! String)!
        tokenURL = URL(string: server["token_endpoint"] as! String)!
        var register = URLRequest(url: URL(string: server["registration_endpoint"] as! String)!)
        register.httpMethod = "POST"
        register.setValue("application/json", forHTTPHeaderField: "content-type")
        register.httpBody = try JSONSerialization.data(withJSONObject: ["client_name": "Claude", "redirect_uris": [redirect]])
        let (data, _) = try await URLSession.shared.data(for: register)
        clientID = try XCTUnwrap((JSONSerialization.jsonObject(with: data) as? [String: Any])?["client_id"] as? String)
    }

    func authorize() async throws -> Attempt {
        let verifier = Data((0 ..< 32).map { _ in UInt8.random(in: 0 ... 255) }).base64URL
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var parts = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            .init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect), .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "state", value: "e2e"),
            .init(name: "resource", value: mcpURL.absoluteString),
        ]
        let (data, _) = try await URLSession.shared.data(from: parts.url!)
        let html = String(decoding: data, as: UTF8.self)
        let ask = try XCTUnwrap(html.firstMatch(of: /const ask = \{ request: "([^"]+)", secret: "([^"]+)" \}/), html)
        let shown = try XCTUnwrap(html.firstMatch(of: /id="number">(\d+)</).flatMap { Int($0.1) }, html)
        let pollURL = authorizeURL.deletingLastPathComponent().appendingPathComponent("poll")
        return Attempt(request: String(ask.1), secret: String(ask.2), number: shown, verifier: verifier, pollURL: pollURL)
    }

    /// What the authorize page does: poll until the phone answers, then follow the redirect.
    func waitForRedirect(_ attempt: Attempt) async throws -> String {
        for _ in 0 ..< 40 {
            var poll = URLRequest(url: attempt.pollURL)
            poll.httpMethod = "POST"
            poll.setValue("application/json", forHTTPHeaderField: "content-type")
            poll.httpBody = try JSONSerialization.data(withJSONObject: ["request": attempt.request, "secret": attempt.secret])
            let (data, _) = try await URLSession.shared.data(for: poll)
            let out = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            if out["status"] as? String == "done" {
                return try XCTUnwrap(out["location"] as? String)
            }
            try await Task.sleep(for: .milliseconds(750))
        }
        throw XCTSkip("the phone never answered")
    }

    func finish(_ attempt: Attempt) async throws -> Tokens {
        let location = try await waitForRedirect(attempt)
        let code = try XCTUnwrap(URLComponents(string: location)?.queryItems?.first { $0.name == "code" }?.value, location)
        var exchange = URLRequest(url: tokenURL)
        exchange.httpMethod = "POST"
        exchange.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "grant_type", value: "authorization_code"), .init(name: "code", value: code),
            .init(name: "redirect_uri", value: redirect), .init(name: "client_id", value: clientID),
            .init(name: "code_verifier", value: attempt.verifier),
        ]
        exchange.httpBody = Data(form.percentEncodedQuery!.utf8)
        let (data, _) = try await URLSession.shared.data(for: exchange)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Tokens(accessToken: try XCTUnwrap(body["access_token"] as? String, "\(body)"))
    }

    func searchPeople(_ query: String, token: String) async throws -> String {
        var call = URLRequest(url: mcpURL)
        call.httpMethod = "POST"
        call.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        call.setValue("application/json", forHTTPHeaderField: "content-type")
        call.setValue("application/json, text/event-stream", forHTTPHeaderField: "accept")
        call.setValue("2025-06-18", forHTTPHeaderField: "mcp-protocol-version")
        call.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": "search_people", "arguments": ["query": query]],
        ])
        let (data, _) = try await URLSession.shared.data(for: call)
        return String(decoding: data, as: UTF8.self)
    }

    private static func json(_ url: URL) async throws -> [String: Any] {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
