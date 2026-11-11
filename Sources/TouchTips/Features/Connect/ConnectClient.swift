// The clients you can connect, and what each needs. Every path here comes from docs/connectors.md.

import SwiftUI
import UIKit

enum ConnectClient: String, CaseIterable, Identifiable, Hashable, Sendable {
    case claude, chatgpt, grokBot = "grok", instinct, other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: "Claude"
        case .chatgpt: "ChatGPT"
        case .grokBot: "Grok Bot"
        case .instinct: "Instinct"
        case .other: "Any agent"
        }
    }

    var icon: ImageResource {
        switch self {
        case .claude: .brandClaude
        case .chatgpt: .brandChatgpt
        case .grokBot: .brandGrokbot
        case .instinct: .brandInstinct
        case .other: .plugs
        }
    }

    /// After the clipboard is filled. One action each.
    var steps: [String] {
        switch self {
        case .claude: ["Check the name and URL, then Continue.", "No sign-in → Add."]
        case .chatgpt: ["+ → Add custom MCP server → paste the URL.", "No authentication → Create."]
        case .grokBot: ["In any chat with your Bot, paste the message.", "Confirm when the Bot repeats it back."]
        case .instinct: ["Settings → MCP connections → name TouchTips, this URL.", "Not there? Instinct hasn't opened custom MCP to everyone yet."]
        case .other: ["Give it the URL as an MCP server, no auth."]
        }
    }

    /// What goes on the clipboard. Grok Bot takes the server as a chat message, so the message is the clipboard.
    func clipboardText(for url: String) -> String {
        switch self {
        case .grokBot: "Add this MCP server: \(url)"
        default: url
        }
    }

    /// How "Open" gets in. `.app` hands off to iOS, which opens the client's app when it claims the link.
    /// `.web` stays in an in-app browser, for clients whose iOS app can't take a server.
    enum Way {
        case app(URL)
        case web(URL)
    }

    @MainActor
    func way(for url: String) -> Way? {
        switch self {
        case .claude:
            // Anthropic's install link: the add-custom-connector dialog, prefilled. claude.ai's universal-link
            // file routes exactly this form into the Claude iOS app.
            var parts = URLComponents(string: "https://claude.ai/customize/connectors")!
            parts.queryItems = [
                URLQueryItem(name: "modal", value: "add-custom-connector"),
                URLQueryItem(name: "connectorName", value: "TouchTips"),
                URLQueryItem(name: "connectorUrl", value: url),
            ]
            return parts.url.map { .app($0) }
        case .chatgpt:
            // The ChatGPT iOS app can't add servers (web only), so keep its universal link out of the way.
            return URL(string: "https://chatgpt.com/plugins?no_universal_links=1").map { .web($0) }
        case .grokBot:
            if let scheme = URL(string: "grokbot://"), UIApplication.shared.canOpenURL(scheme) {
                return .app(scheme)
            }
            return URL(string: "https://apps.apple.com/app/id6794501026").map { .app($0) }
        case .instinct:
            return URL(string: "https://app.instinct.com/settings").map { .web($0) }
        case .other:
            return nil
        }
    }

    var openLabel: String {
        switch self {
        case .grokBot: "Open Grok Bot"
        case .instinct: "Open Instinct settings"
        default: "Open \(name)"
        }
    }

    /// Clients you reach by messaging them lead with Share.
    var sharesFirst: Bool {
        switch self {
        case .grokBot, .instinct, .other: true
        case .claude, .chatgpt: false
        }
    }

    static func claudeCodeCommand(_ url: String) -> String {
        "claude mcp add --transport http touchtips --scope user \(url)"
    }

    static func from(path: String) -> ConnectClient? {
        ConnectClient(rawValue: path)
    }
}
