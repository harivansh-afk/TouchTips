// The clients you can connect, and what each needs. Mirrors web/src/lib/connect.ts.

import Foundation
import SwiftUI

enum ConnectClient: String, CaseIterable, Identifiable, Hashable, Sendable {
    case claude, chatgpt, claudeCode = "claude-code", instinct, grok, other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: "Claude"
        case .chatgpt: "ChatGPT"
        case .claudeCode: "Claude Code"
        case .instinct: "Instinct"
        case .grok: "Grok"
        case .other: "Any agent"
        }
    }

    var icon: ImageResource {
        switch self {
        case .claude, .claudeCode: .brandClaude
        case .chatgpt: .brandChatgpt
        case .instinct: .brandInstinct
        case .grok: .brandGrok
        case .other: .plugs
        }
    }

    /// After the URL is on the clipboard. One action each.
    var steps: [String] {
        switch self {
        case .claude: ["Settings → Connectors → Add custom connector", "Paste the URL. Add."]
        case .chatgpt: ["Settings → Apps & Connectors → Developer mode", "Create → paste the URL, no authentication."]
        case .claudeCode: ["Paste the command in a terminal."]
        case .instinct: ["Connections → add an MCP server", "Paste the URL."]
        case .grok: ["Settings → Connectors", "Paste the URL."]
        case .other: ["Give it the URL as an MCP server, no auth."]
        }
    }

    /// Where "Open" goes: the place in that client where the URL gets pasted. Nil when there is no such place.
    var openURL: URL? {
        switch self {
        case .claude: URL(string: "https://claude.ai/settings/connectors")
        case .chatgpt: URL(string: "https://chatgpt.com/#settings/Connectors")
        case .instinct: URL(string: "https://app.instinct.com")
        case .grok: URL(string: "https://grok.com")
        case .claudeCode, .other: nil
        }
    }

    /// What goes on the clipboard the moment the key exists.
    func clipboardText(for url: String) -> String {
        switch self {
        case .claudeCode: "claude mcp add --transport http touchtips \(url)"
        default: url
        }
    }

    static func from(path: String) -> ConnectClient? {
        ConnectClient(rawValue: path)
    }
}
