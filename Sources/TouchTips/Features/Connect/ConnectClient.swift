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

    /// Step one's title: the clipboard is already filled when the screen appears.
    var copiedTitle: String {
        self == .grokBot ? "Your message is copied" : "Your link is copied"
    }

    /// The step the Open button sits in. Its title says where Open goes, so the button doesn't have to.
    var openTitle: String {
        switch self {
        case .claude: "Open Claude"
        case .chatgpt: "Open ChatGPT on the web"
        case .grokBot: "Open Grok Bot"
        case .instinct: "Open your Instinct settings"
        case .other: "Open your agent"
        }
    }

    var openDetail: String? {
        switch self {
        case .claude: "TouchTips and your link are already filled in."
        case .chatgpt: "ChatGPT's app can't add servers yet."
        default: nil
        }
    }

    /// What's left once the client is open, one action per line. `**Bold**` marks words on the client's screen.
    var finish: [String] {
        switch self {
        case .claude: ["Tap **Continue**, choose **No sign-in**, then tap **Add**."]
        case .chatgpt: [
                "Tap **+**, then **Add custom MCP server**, and paste the link.",
                "Choose **No authentication**, then tap **Create**.",
            ]
        case .grokBot: [
                "Paste the message into a chat with your Bot.",
                "Confirm when it reads the server back.",
            ]
        case .instinct: [
                "Find **MCP connections** and add one named **TouchTips**.",
                "Paste the link.",
            ]
        case .other: [
                "Add the link to your agent as a remote MCP server.",
                "Leave authentication off.",
            ]
        }
    }

    /// A caveat under the steps, for clients where the path isn't there for everyone.
    var note: String? {
        switch self {
        case .instinct: "No MCP connections in your settings? Instinct hasn't turned it on for every account yet."
        default: nil
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

    static func claudeCodeCommand(_ url: String) -> String {
        "claude mcp add --transport http touchtips --scope user \(url)"
    }

    static func from(path: String) -> ConnectClient? {
        ConnectClient(rawValue: path)
    }
}
