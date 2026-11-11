// The clients you can connect, and what each needs. Mirrors web/src/lib/connect.ts.

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

    /// After the URL is on the clipboard. One action each.
    var steps: [String] {
        switch self {
        case .claude: ["Settings → Connectors → Add custom connector", "Paste the URL. Add."]
        case .chatgpt: ["Settings → Apps & Connectors → Developer mode", "Create → paste the URL, no authentication."]
        case .grokBot: ["Tell your Bot: add this MCP server. Paste the URL.", "Or Connect apps → Add a custom connector → Remote HTTPS."]
        case .instinct: ["Text Instinct: connect this MCP server. Paste the URL.", "Or Settings → MCP connections → name TouchTips, this URL."]
        case .other: ["Give it the URL as an MCP server, no auth."]
        }
    }

    /// The client's own app when it is installed, else the page in it where the URL gets pasted.
    /// Nil when the way in is sharing the URL into a conversation.
    @MainActor
    var openURL: URL? {
        switch self {
        case .claude:
            if let scheme = URL(string: "claude://"), UIApplication.shared.canOpenURL(scheme) {
                return scheme
            }
            return URL(string: "https://claude.ai/settings/connectors")
        case .chatgpt:
            // chatgpt.com is a universal link; the app takes it when installed.
            return URL(string: "https://chatgpt.com/#settings/Connectors")
        case .instinct:
            return URL(string: "https://app.instinct.com")
        case .grokBot, .other:
            return nil
        }
    }

    /// Clients you reach by messaging them: Share leads, Open follows.
    var sharesFirst: Bool {
        switch self {
        case .grokBot, .instinct, .other: true
        case .claude, .chatgpt: false
        }
    }

    static func claudeCodeCommand(_ url: String) -> String {
        "claude mcp add --transport http touchtips \(url)"
    }

    static func from(path: String) -> ConnectClient? {
        ConnectClient(rawValue: path)
    }
}
