# Adding a custom remote MCP server to each client

Research date: 2026-11-11. Every claim cites a URL. Items marked UNVERIFIED could not be confirmed from a primary source. "Third-party" marks setup guides from companies other than the client's maker.

Our server: `https://touchtips.app/c/<key>/mcp`, remote MCP over Streamable HTTP, no authentication. The iPhone app copies that URL to the clipboard, shows an "Open <client>" button and one or two step lines.

## Summary

- **Instinct**: custom MCP is not a documented or generally available feature. Three third-party guides say some accounts show an "MCP connections" area in settings with name, URL and header fields; a developer issue closed on 2026-10-05 says there is "no custom-MCP connector intake". No URL scheme is documented. The iOS app exists in Apple's universal-link file for instinct.com but is not on the public App Store. Ship an "Open Instinct settings" button to `https://app.instinct.com/settings` with a hedge, and offer the email route as the fallback.
- **Grok Bot**: no settings form on mobile; the documented way on every surface is to ask the Bot in chat ("Add this MCP server: <url>"). Desktop also has a manual "Add a custom connector" form. A `grokbot://` scheme exists but no documented link opens Connect apps; a prompt-prefill link (`grokbot://app/v1/prompt?id=<bot>&text=...`) was announced by Cursor staff on 2026-10-16 as "coming in an upcoming update" (UNVERIFIED that it has shipped).
- **Claude**: web and desktop add custom connectors under Customize > Connectors > Add > Add custom connector, with Authentication "No sign-in". Mobile adding is "in beta"; web/desktop are the primary path. Anthropic publishes an install link that prefills name and URL, and claude.ai's universal-link file routes exactly that link into the Claude iOS app.
- **ChatGPT**: current path is chatgpt.com/plugins > + > Add custom MCP server; authentication can be "No authentication". OpenAI's help centre says custom MCP servers are "web only", and only Business/Enterprise/Edu get full MCP (Pro: read/fetch). There is no documented `chatgpt://` scheme; chatgpt.com/plugins is a universal link into the iOS app, which cannot add servers.
- **Claude Code**: `claude mcp add --transport http <name> <url>` with `--scope user` for all projects.

## 1. Instinct

### Surfaces

- Primary interface is messaging: "there are no new interfaces. You can text or call it." [instinct.com](https://instinct.com). Channels are iMessage, WhatsApp, email and phone calls; the agent has its own mailbox at mail.instinct.com. [crosswalk.to/agents/instinct](https://crosswalk.to/agents/instinct), [eesel.ai (third-party, 2026-09-28)](https://www.eesel.ai/blog/instinct-ai)
- Web workspace at `https://app.instinct.com`: sign in with a phone number and a texted code. [eesel.ai (third-party)](https://www.eesel.ai/blog/instinct-ai). Documented routes: `app.instinct.com/settings` (training opt-out) and `app.instinct.com/workspace` (delete indexed data). [instinct.com/privacy](https://instinct.com/privacy)
- Mac app: the privacy policy covers "the related Mac OS and mobile applications (the 'App')" [instinct.com/privacy](https://instinct.com/privacy). A hands-on review says "There is also a Mac app and a web workspace at app.instinct.com, where you manage connections and settings." [eesel.ai review (third-party)](https://www.eesel.ai/blog/instinct-ai-review). A leak report on 2026-08-29 described the Mac app as in development. [runtimewire.com (third-party)](https://runtimewire.com/article/instinct-mac-app-imessage-local-browser-whoop)
- iOS app: Apple's universal-link file at `https://app.instinct.com/.well-known/apple-app-site-association` (and the same file on instinct.com) declares app ID `PZU5FB643S.co.instinct.mobile` with paths `/vault`, `/vault/*`, `/workspace`, `/workspace/*`, `/mailbox`, `/connect`, `/connect/*`, `/session/connect/*`, `/session/vault/*`, `/link-icloud`, `/whatsapp-onboarding` (fetched 2026-11-11). The App Store lookup API for bundle `co.instinct.mobile` returns zero results (`https://itunes.apple.com/lookup?bundleId=co.instinct.mobile`, 2026-11-11), so the app is not publicly listed. UNVERIFIED: whether it is in TestFlight or members-only. Reviews consistently say "There's no app to download". [top5apps.ai (third-party, 2026-11-01)](https://top5apps.ai/best-ai-apps/best-personal-ai-agents/instinct/). The Verge hands-on of 2026-10-09 is quoted secondhand as "There's no app and no monthly subscription fee (for now)"; theverge.com blocks our fetcher, so that quote is UNVERIFIED at source. [cellcog.ai (third-party)](https://cellcog.ai/blog/what-is-instinct-ai/)

### Custom MCP: status

Instinct publishes no documentation on MCP. Checks of its homepage, sign-in page and sitemap found none as of 2026-10-04. [pearmcp.com (third-party)](https://pearmcp.com/guides/instinct)

Evidence that some accounts have it:

- "Some accounts have MCP connections in their settings"; one person "connected to crosswalk that way on October 16, 2026"; "Instinct does not document them, and most people who made a crosswalk key for Instinct never got to use it." [crosswalk.to/agents/instinct/mcp (third-party)](https://crosswalk.to/agents/instinct/mcp)
- "Add https://mcp.unifygtm.com/mcp to the MCP connections in your Instinct account." Prerequisite: "permission to configure MCP connections". Workflow "has not been tested end to end." [unifygtm.com (third-party)](https://www.unifygtm.com/integrations/instinct)
- "Instinct has not published steps for adding your own MCP server." "Open your Instinct settings and look for a place to add an MCP server or custom connector. If you do not see one, Instinct does not offer it for your account yet." [freddy.coach (third-party)](https://freddy.coach/help/connect-instinct)

Evidence against general availability:

- Developer issue opened 2026-09-18: "Instinct does not currently have a supported way to register a custom remote MCP server"; closed 2026-10-05 as not planned: "Instinct has no custom-MCP connector intake, so there is nothing to register the URL with." [github.com/nbramia/LifeOS/issues/1150](https://github.com/nbramia/LifeOS/issues/1150)
- awaken.tax/docs/consumer/instinct-mcp returned HTTP 403 to our fetcher; not read. UNVERIFIED.

Conclusion: custom MCP in Instinct is not generally available and not documented by Instinct. Treat it as a hidden or staged feature.

### Path (if the account has it)

- Where: "your Instinct settings" showing "MCP connections". No menu breadcrumb is published; the only settings URL documented by Instinct is `https://app.instinct.com/settings`. [crosswalk.to/agents/instinct/mcp](https://crosswalk.to/agents/instinct/mcp), [instinct.com/privacy](https://instinct.com/privacy)
- Fields reported: connection **name**, **URL**, and an optional **header** (`Authorization: Bearer <key>`). [crosswalk.to/agents/instinct/mcp](https://crosswalk.to/agents/instinct/mcp). freddy's guide lists Name and URL only and describes an OAuth approval page. [freddy.coach](https://freddy.coach/help/connect-instinct)
- Can you connect by texting the URL? No source documents that. Texting is used only after connection ("text Instinct 'check crosswalk'"). [crosswalk.to](https://crosswalk.to/agents/instinct/mcp). freddy warns "Do not paste a key or email code into a text message to Instinct." [freddy.coach](https://freddy.coach/help/connect-instinct). UNVERIFIED whether a texted URL does anything.

### Officially supported ways to give Instinct outside data

- Connected accounts: the privacy policy names Google Workspace ("Google Calendar, Gmail, Google Drive, Google Docs, Google Sheets, Google Slides and Google Tasks") and "applications and services you have connected"; disconnect "via your settings within Instinct's Workspace". [instinct.com/privacy](https://instinct.com/privacy). A hands-on screenshot listed "Google Workspace, Outlook, Linear, Notion, GitHub, Slack, Granola and Shop Pay" as connectors. [eliotprince.com (third-party, 2026-10-06)](https://eliotprince.com/blog/instinct-ai-personal-assistant)
- Email: each agent has its own mailbox at mail.instinct.com and can be looped into threads; crosswalk calls the email route "the default when MCP is absent". [crosswalk.to/agents/instinct](https://crosswalk.to/agents/instinct)
- Vault: logins, cards and personal info the agent can use to sign in on your behalf. [eliotprince.com (third-party)](https://eliotprince.com/blog/instinct-ai-personal-assistant), [instinct.com/privacy](https://instinct.com/privacy)
- Instinct-to-Instinct agent protocol (talks to other Instincts only). [crosswalk.to/agents/instinct](https://crosswalk.to/agents/instinct)
- Composio: only the open-source clone "Open Instinct" is built on Composio. [github.com/mariagorskikh/open-instinct](https://github.com/mariagorskikh/open-instinct), [composio.dev/built-with/open-instinct](https://composio.dev/built-with/open-instinct). A vendor page claims the real Instinct connects apps via Composio with no evidence. [agent37.com (third-party)](https://www.agent37.com/docs/agents-api/instinct). UNVERIFIED for the real product.

### Deep link

- No URL scheme or universal link into settings is documented anywhere. The universal-link file maps `/connect`, `/connect/*`, `/workspace`, `/vault` to the unreleased iOS app (see Surfaces); nothing maps `/settings`. With no public app, `https://app.instinct.com/settings` opens in Safari.

### Sources

instinct.com, instinct.com/privacy, app.instinct.com AASA, crosswalk.to/agents/instinct, crosswalk.to/agents/instinct/mcp, freddy.coach/help/connect-instinct, unifygtm.com/integrations/instinct, pearmcp.com/guides/instinct, github.com/nbramia/LifeOS/issues/1150, github.com/mariagorskikh/open-instinct, eesel.ai, eliotprince.com, runtimewire.com, top5apps.ai, cellcog.ai.

## 2. Grok Bot

### Surfaces

- "Work with Bots on desktop, mobile, in Slack, or on X." [docs.x.ai/grok-bot/overview](https://docs.x.ai/grok-bot/overview)
- Desktop app for macOS, Windows, Linux; download at `https://x.ai/bot` or `https://cursor.com/dashboard/bot`. Phone: "install Grok Bot from the App Store or Google Play and sign in with the same account"; iPhone needs iOS 18+. [docs.x.ai/grok-bot/get-started](https://docs.x.ai/grok-bot/get-started)
- iOS App Store: `https://apps.apple.com/app/id6794501026` [docs.x.ai/grok-bot/mobile](https://docs.x.ai/grok-bot/mobile); App Store lookup confirms id 6794501026, bundle `co.anysphere.sand`, seller X Corp., version 1.24.1 (2026-11-05).
- Web app: none documented; the docs describe only desktop, mobile and the Bot's cloud computer. [docs.x.ai/grok-bot/computer-and-apps](https://docs.x.ai/grok-bot/computer-and-apps), [cursor.com/docs/grok-bot/get-started](https://cursor.com/docs/grok-bot/get-started)
- Account: a Cursor account; help pages live at cursor.com/help/grok-bot. [docs.x.ai/grok-bot/get-started](https://docs.x.ai/grok-bot/get-started)

### Path

Desktop, manual form:
- "Open Connect apps from the sidebar, or follow an in-chat Connect card." "To add one yourself in the desktop app, choose Add a custom connector at the bottom of Connect apps." "Enter a Name, then pick a Type." "Remote HTTPS takes a Server URL, with optional HTTP headers and an OAuth Client ID." "Choose Add plugin to save it." [docs.x.ai/grok-bot/computer-and-apps](https://docs.x.ai/grok-bot/computer-and-apps)

Any surface, by chat (the docs' own words):
- "A Bot can also add an MCP server that isn't in the catalog, by URL or by a command that runs on its computer." "Adding a server on a private network, or one that uses a private certificate authority, asks for your approval first." [docs.x.ai/grok-bot/computer-and-apps](https://docs.x.ai/grok-bot/computer-and-apps)
- Cursor staff (Colin) on the forum: "There isn't a settings form for this, but you can still add custom connectors." "Grok Bot manages connectors through the chat itself: just tell your bot to add your MCP server, for example 'Add this MCP server: https://your-app.example.com/mcp' and it will confirm the details with you and set it up." "New tools become available from your next message." Server must be "a public HTTPS URL, using streamable HTTP or SSE". [forum.cursor.com/t/grokbot-custom-connectors/169965](https://forum.cursor.com/t/grokbot-custom-connectors/169965)

iPhone app:
- "In the mobile app, tap your avatar on the top left and choose Connect apps." [docs.x.ai/grok-bot/computer-and-apps](https://docs.x.ai/grok-bot/computer-and-apps). The mobile page lists "Settings → Connect apps" and "Install or review plugins" under Settings. [docs.x.ai/grok-bot/mobile](https://docs.x.ai/grok-bot/mobile)
- The manual "Add a custom connector" form is documented for desktop only; the docs do not say whether it exists on the phone. UNVERIFIED. A forum bug report reproduces "Open Grok Bot on iOS" > "Open Plugins and connect ... the custom MCP server" (Aug 2026), and Cursor staff said on 2026-10-13 that "Connecting plugins and custom MCP servers from Grok Bot on iOS was reworked" so sign-in "happens in a sheet inside the app". [forum.cursor.com/t/.../168330](https://forum.cursor.com/t/grok-bot-ios-mcp-oauth-browser-flow-does-not-return-to-the-app/168330). The chat method needs no form and works wherever you can message the Bot.

Help page `cursor.com/help/grok-bot/connect-apps` covers catalog apps only; it has no custom-MCP steps. [cursor.com/help/grok-bot/connect-apps](https://cursor.com/help/grok-bot/connect-apps)

### Fields

Name; Type = Remote HTTPS; Server URL; optional HTTP headers; optional OAuth Client ID (Client Secret appears once an ID is entered). Save with "Add plugin". [docs.x.ai/grok-bot/computer-and-apps](https://docs.x.ai/grok-bot/computer-and-apps). For our no-auth server: Name and Server URL only.

### Deep link

- Scheme `grokbot://` exists. Documented forms (Cursor forum, staff replies):
  - `grokbot://app/v1/prompt?id=<botId>&text=<url-encoded one line, max 1000 chars>` opens a Bot with the text prefilled, "never sent automatically", only fills an empty composer. Web handoff: `https://cursor.com/grok-bot/link/v1/prompt?id=<botId>&text=...`. Announced 2026-10-16 as "coming in an upcoming Grok Bot update". Bot id = last segment of the Bot's "Copy link". [forum.cursor.com/t/.../174986](https://forum.cursor.com/t/support-passing-parameters-through-grok-bot-deep-links/174986). UNVERIFIED that it has shipped and whether the mobile app handles it.
  - `grokbot://app/v1/sidebar?tab=routines` and webhook-field links: "aren't handled by the mobile app yet" (2026-10-09). [forum.cursor.com/t/webhook-credentials-in-app-links-grokbot](https://forum.cursor.com/t/webhook-credentials-in-app-links-grokbot)
  - `grokbot://app/v1/settings?id=...` appears only in a third-party repo. [github.com/diegofornalha/meu-bot/pull/182](https://github.com/diegofornalha/meu-bot/pull/182). UNVERIFIED.
- No link to Connect apps or to the custom-connector form is documented on docs.x.ai or cursor.com.
- Universal links: `https://x.ai/.well-known/apple-app-site-association` routes `/bot/plugin/?*`, `/bot/agent/?*` and `/bot/<21-char share id>` into the Grok Bot app; `https://cursor.com/.well-known/apple-app-site-association` routes only `/bot/sign-in/return`, `/bot/sign-in/confirm` and `/bot/1password/oauth/callback` (fetched 2026-11-11). Neither opens settings.

### Sources

docs.x.ai/grok-bot/overview, docs.x.ai/grok-bot/get-started, docs.x.ai/grok-bot/computer-and-apps, docs.x.ai/grok-bot/mobile, cursor.com/docs/grok-bot/get-started, cursor.com/help/grok-bot/connect-apps, forum.cursor.com threads 169965, 168330, 174986, webhook-credentials-in-app-links-grokbot (Cursor staff replies), x.ai and cursor.com AASA files, App Store lookup.

## 3. Claude

### Surfaces

- "Custom connectors using remote MCP are available on Claude, Cowork, and Claude Desktop for users on Free, Pro, Max, Ultra, Team, and Enterprise plans. Free users are limited to one custom connector." [support.claude.com/11175166](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)
- Mobile: "Installing connectors on mobile is currently in beta—Claude Desktop and web remain the primary path for custom connectors." A connector added on web or desktop "will be available to use the next time you log in to your account on Claude for iOS or Android." [support.claude.com/11176164](https://support.claude.com/en/articles/11176164-use-connectors-to-extend-claude-s-capabilities). The older article said "It's not possible to add new connectors (custom or from the directory) on Claude for iOS or Android at this time." [support.anthropic.com/11724452](https://support.anthropic.com/en/articles/11724452-browsing-and-connecting-to-tools-from-the-directory)
- Remote connectors are reached from Anthropic's cloud for every client, "including claude.ai, Claude Desktop, Cowork, and the mobile apps." [support.claude.com/11175166](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)
- iOS App Store: `https://apps.apple.com/us/app/claude-by-anthropic/id6473753684`, bundle `com.anthropic.claude` (App Store lookup, 2026-11-11).

### Path (web and desktop; same account-level flow)

1. Customize > Connectors (`https://claude.ai/customize/connectors`).
2. "Select Add, then Add custom connector." (Support article wording: "Click Add", "Hover over Custom, then select Web".)
3. "Enter a name for the connector and the remote MCP server URL, then click Continue."
4. Authentication: "No sign-in: anyone with access to the server URL can use the connector." With No sign-in, "You won't see the OAuth client setting."
5. "Click Add."

[claude.com/docs/connectors/custom/remote-mcp](https://claude.com/docs/connectors/custom/remote-mcp), [support.claude.com/11176164](https://support.claude.com/en/articles/11176164-use-connectors-to-extend-claude-s-capabilities), [support.claude.com/11175166](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)

Desktop app: no separate path; the article lists Claude Desktop as a surface and the dialog is the same account-level Customize > Connectors. Desktop extensions (local `.mcpb` under Settings > Extensions) are a different thing and not needed. [claude.com/docs/connectors/custom/remote-mcp](https://claude.com/docs/connectors/custom/remote-mcp)

iOS app: adding is "in beta" (see Surfaces); no mobile click path is published. Use the install link below and let the app or browser handle it; otherwise add on web and it syncs.

### Fields

Name; MCP server URL ("the HTTPS address where the server accepts MCP requests, for example https://mcp.example.com/mcp"); Authentication (Sign in now / Sign in when needed / No sign-in); OAuth client (hidden for No sign-in); Request headers (beta, "available to a limited set of organizations"); Advanced > Transport (leave default; `/sse` selects SSE). [claude.com/docs/connectors/custom/remote-mcp](https://claude.com/docs/connectors/custom/remote-mcp)

### Deep link

- Official install link that prefills the dialog: `https://claude.ai/customize/connectors?modal=add-custom-connector&connectorName=NAME&connectorUrl=ENCODED_URL`. "claude.ai opens the dialog with the name and URL prefilled and shows a notice that the values came from an external link. The user reviews the values and confirms before anything is added. A signed-out user is prompted to sign in first." [claude.com/docs/connectors/building/directory-vs-custom](https://claude.com/docs/connectors/building/directory-vs-custom)
- Universal-link coverage: `https://claude.ai/.well-known/apple-app-site-association` (fetched 2026-11-11) lists for app ID `Q6L2SF6YDW.com.anthropic.claude` the component `{"/": "/customize/connectors", "?": {"modal": "add-custom-connector"}}`, and excludes `/customize/connectors` with `step=` or `oauth_error=`. So the install link above opens the Claude iOS app when installed; plain `https://claude.ai/customize/connectors` or `https://claude.ai/settings/connectors` is not listed and opens in the browser. What the iOS app shows after opening the link is not documented (mobile adding is "in beta"). UNVERIFIED on device.
- `claude://` scheme on mobile: documented routes are only `claude://code`, `claude://code/{session-id}`, `claude://code/new?q=&repo=&branch=`, plus `https://claude.ai/code/...` universal links; "These links require Claude Code access on your account." No settings or connectors route. [support.claude.com/14898120](https://support.claude.com/en/articles/14898120-open-the-claude-mobile-app-with-a-link)
- `claude://` on desktop: `claude://claude.ai/new`, `claude://claude.ai/chat/{id}`, `claude://claude.ai/project/{id}`, `claude://code/new`, `claude://cowork/new`; no connectors route. [support.claude.com/14729294](https://support.claude.com/en/articles/14729294-open-claude-desktop-with-a-link)

### Sources

support.claude.com articles 11175166, 11176164, 14898120, 14729294; support.anthropic.com 11724452; claude.com/docs/connectors/custom/remote-mcp; claude.com/docs/connectors/building/directory-vs-custom; claude.ai AASA; App Store lookup.

## 4. ChatGPT

### Surfaces

- "Custom MCP server connections and full MCP support are available for ChatGPT Business and Enterprise/Edu customers on ChatGPT web." "Pro users can connect custom MCP servers with read/fetch permissions." "Can I connect custom MCP servers on mobile? No - web only." [help.openai.com/12584461](https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt)
- Free and Plus are not listed as eligible in that article. UNVERIFIED whether Plus can add one today (2025 reports said Plus/Pro had Developer mode). [venturebeat.com (third-party, 2025)](https://venturebeat.com/dev/openai-adds-powerful-but-dangerous-support-for-mcp-in-chatgpt-dev-mode)
- iOS App Store: `https://apps.apple.com/us/app/chatgpt/id6448311069`, bundle `com.openai.chat` (App Store lookup, 2026-11-11).

### Path (web)

Current, per OpenAI: "In the current Plugins experience, add a custom MCP server directly from Plugins. You don't need to turn on Developer Mode first."
1. "Go to Plugins." (`https://chatgpt.com/plugins`)
2. "Select the plus button, then select Add custom MCP server."
3. "Enter a name and, optionally, a description."
4. "Under Connection, enter your server's public HTTPS MCP endpoint URL, or select Tunnel ..."
5. "Configure authentication for your server."
6. "Review the risk warning and select the I understand and want to continue checkbox."
7. "Select Create as a plugin, then review the discovered tools and metadata."
Then install the plugin and type `@` in the prompt box to pick it. [help.openai.com/12584461](https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt), [developers.openai.com/api/docs/guides/custom-mcp-server](https://developers.openai.com/api/docs/guides/custom-mcp-server), [developers.openai.com/plugins/deploy/connect-chatgpt](https://developers.openai.com/plugins/deploy/connect-chatgpt)

Legacy path (still in the help article as "Legacy custom app configuration"): "from user settings, go to Apps > Create", provide endpoint, "Pick the authentication mechanism", "Select Scan Tools". [help.openai.com/12584461](https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt). The older "Settings → Connectors → Advanced → Developer mode" route is third-party reporting from 2025 and no longer the documented path. [venturebeat.com (third-party)](https://venturebeat.com/dev/openai-adds-powerful-but-dangerous-support-for-mcp-in-chatgpt-dev-mode). The old platform.openai.com developer-mode guide now returns 404 (`https://developers.openai.com/api/docs/guides/developer-mode`, 2026-11-11).

### Fields

Name; optional description; Connection: Server URL (or Tunnel); Authentication: "OAuth", "No authentication", or "OAuth or no authentication"; risk acknowledgement. "Supported MCP protocols: SSE and streaming HTTP." [developers.openai.com/api/docs/guides/custom-mcp-server](https://developers.openai.com/api/docs/guides/custom-mcp-server)

### iOS app

Cannot add custom MCP servers: "No - web only." [help.openai.com/12584461](https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt). Whether mobile Safari on chatgpt.com shows the add button is UNVERIFIED.

### Deep link

- No `chatgpt://` scheme is documented. OpenAI's desktop app uses `codex://` (e.g. `codex://settings`), desktop only. [learn.chatgpt.com/docs/reference/commands](https://learn.chatgpt.com/docs/reference/commands)
- Universal links: `https://chatgpt.com/.well-known/apple-app-site-association` (fetched 2026-11-11) routes into the ChatGPT iOS app: `/plugins` ("Matches the plugins root page"), `/plugins/*`, `/settings` ("Opens the settings root page directly in the app"), `/settings/security`, and legacy hash links `#settings` and `#settings/Connectors?connector=*` ("Opens specific connector settings deep links in-app"). It does not list `/settings/plugins-settings`. Any URL with `?no_universal_links=1` or `#no_universal_links` is excluded and stays in the browser.
- `https://chatgpt.com/#settings/Connectors` (no `connector=` value): matches only `#settings` root behaviour at best; UNVERIFIED what the app shows.
- A developer reported on 2026-11-04 that `/plugins/*` links open the iOS app, which "then immediately redirects to Safari". No staff reply. [community.openai.com/t/1412807](https://community.openai.com/t/plugin-directory-links-chatgpt-com-plugins-open-the-ios-app-and-then-redirect-to-safari/1412807)
- Practical consequence: since the app cannot add servers, open `https://chatgpt.com/plugins` in an in-app Safari view (SFSafariViewController does not trigger universal links) or append `?no_universal_links=1`.

### Sources

help.openai.com/12584461 (read via a text proxy because the site returns 403 to plain fetches), developers.openai.com custom-mcp-server and plugins/deploy/connect-chatgpt, chatgpt.com AASA, community.openai.com 1412807, learn.chatgpt.com commands reference, App Store lookup.

## 5. Claude Code

- "HTTP servers are the recommended option for connecting to remote MCP servers."
- `claude mcp add --transport http <name> <url>`; example `claude mcp add --transport http notion https://mcp.notion.com/mcp`. Headers via `--header "Authorization: Bearer ..."` (short forms `-t`, `-H`). Not needed for our server.
- Scope: `-s` / `--scope`: `local` (default, "available only to you in the current project", stored in `~/.claude.json`), `project` (shared via `.mcp.json`), `user` ("available to you across all projects"). "Each command writes to local scope unless you add --scope project or --scope user."
- Check: `claude mcp list` shows "✔ Connected", "! Needs authentication" or "✘ Failed to connect". "Claude Code marks a remote server as needing authentication when the server responds with 401 Unauthorized or 403 Forbidden."
- JSON alias: `type` accepts `streamable-http` as an alias for `http`.

[code.claude.com/docs/en/mcp](https://code.claude.com/docs/en/mcp)

Recommended command for us: `claude mcp add --transport http touchtips --scope user https://touchtips.app/c/<key>/mcp`.

## What we should ship

| Client | Button label | URL or scheme to open | Steps text (max 2 lines) |
| - | - | - | - |
| Claude | Open Claude | `https://claude.ai/customize/connectors?modal=add-custom-connector&connectorName=TouchTips&connectorUrl=<percent-encoded URL>` (opens the Claude iOS app if installed, else claude.ai; prefilled per Anthropic docs) | 1. Check the prefilled name and URL, tap Continue. 2. Choose "No sign-in", then Add. If the app shows nothing, do it at claude.ai on a computer. |
| ChatGPT | Open ChatGPT | `https://chatgpt.com/plugins?no_universal_links=1` in an in-app browser (the ChatGPT app cannot add servers; web only, Business/Enterprise/Edu full, Pro read-only) | 1. Tap +, then Add custom MCP server; paste the URL. 2. Authentication: No authentication; tick the warning; Create as a plugin. |
| Grok Bot | Open Grok Bot | `grokbot://app/v1/prompt?id=<botId>&text=Add%20this%20MCP%20server%3A%20<encoded URL>` once confirmed to work; until then open the App Store page `https://apps.apple.com/app/id6794501026` or just tell the user to open the app | 1. In any chat with your Bot, send: Add this MCP server: <URL>. 2. Confirm when the Bot repeats the details; tools work from the next message. |
| Instinct | Open Instinct settings | `https://app.instinct.com/settings` (Safari; no public iOS app, no documented scheme) | 1. Look for "MCP connections" in settings; add name TouchTips and the URL (no header). 2. Not every account has this yet; if missing, forward data to your Instinct's email instead. |
| Claude Code | Copy command | none (copy to clipboard) | `claude mcp add --transport http touchtips --scope user <URL>` then `claude mcp list` to see "Connected". |

Notes on the table:
- Claude is the only client with a documented prefilled install link and a universal-link entry for it in the iOS app; still test on device, because mobile adding is "in beta".
- ChatGPT's `#settings/Connectors` hash links exist in the app's universal-link file but the app cannot add a server, so opening the web Plugins page is the only path.
- Grok Bot's prompt link was announced as upcoming on 2026-10-16; test on the current build before shipping it, and fall back to the two step lines.
- Instinct: hedge the copy; the feature is undocumented and the closest developer report says there is no intake at all.
