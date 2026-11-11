// The clients you can connect, and what each needs. Mirrors web/src/lib/connect.ts.

import Foundation

enum ConnectClient: String, CaseIterable, Identifiable, Hashable, Sendable {
    case claude, chatgpt, claudeCode = "claude-code", cursor, vscode, other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: "Claude"
        case .chatgpt: "ChatGPT"
        case .claudeCode: "Claude Code"
        case .cursor: "Cursor"
        case .vscode: "VS Code"
        case .other: "Any agent"
        }
    }

    var tagline: String {
        switch self {
        case .claude: "Web, desktop and iPhone"
        case .chatgpt: "Developer mode"
        case .claudeCode: "One command"
        case .cursor, .vscode: "One click"
        case .other: "Grok, an iMessage bot, your own"
        }
    }

    /// After the URL is on the clipboard. One action per line.
    var steps: [String] {
        switch self {
        case .claude: ["Settings → Connectors → Add custom connector", "Paste the URL, leave authentication off", "Add. Ask Claude when you met someone."]
        case .chatgpt: ["Settings → Apps & Connectors → Advanced → Developer mode on", "Create → paste the URL, authentication: none", "Enable it in a chat. Ask when you met someone."]
        case .claudeCode: ["Paste the command in a terminal", "That's it. Ask in any session."]
        case .cursor: ["Open the install link on the computer running Cursor", "Confirm. Done."]
        case .vscode: ["Open the install link on the computer running VS Code", "Confirm. Done."]
        case .other: ["Give the agent the URL as an MCP server, no auth", "Ask it when you met someone."]
        }
    }

    /// What goes on the clipboard the moment the key exists.
    func clipboardText(for url: String) -> String {
        switch self {
        case .claudeCode: "claude mcp add --transport http touchtips \(url)"
        case .cursor: Self.cursorInstallLink(url)
        case .vscode: Self.vscodeInstallLink(url)
        default: url
        }
    }

    var clipboardLabel: String {
        switch self {
        case .claudeCode: "Command copied"
        case .cursor, .vscode: "Install link copied"
        default: "URL copied"
        }
    }

    static func cursorInstallLink(_ url: String) -> String {
        let config = Data(#"{"url":"\#(url)"}"#.utf8).base64EncodedString()
        return "cursor://anysphere.cursor-deeplink/mcp/install?name=touchtips&config=\(config)"
    }

    static func vscodeInstallLink(_ url: String) -> String {
        let json = #"{"type":"http","url":"\#(url)"}"#
        let encoded = json.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? json
        return "https://vscode.dev/redirect/mcp/install?name=touchtips&config=\(encoded)"
    }

    static func from(path: String) -> ConnectClient? {
        ConnectClient(rawValue: path)
    }
}
