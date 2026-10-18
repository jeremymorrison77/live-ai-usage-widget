# Live AI Usage Widget

A macOS desktop widget that shows how much of your Claude Code and ChatGPT Codex usage limits are left. Small, medium and large widgets come in Clean (default), Solar and Trends styles. Accounts and data stay on your own Mac.

**[Download for Mac (Apple Silicon)](https://github.com/jeremymorrison77/live-ai-usage-widget/releases/latest/download/Live-AI-Usage-Widget-1.0.1-macOS-arm64.zip)** · version 1.0.1 · macOS 14 or later · M1 or newer

<p align="center"><img src="docs/images/overview.png" alt="Settings window and the widget in all sizes and styles" width="100%"></p>

Pictures are drawn from the app's own views with made-up sample readings, not a real account.

**Version 1.0.1.** Apple Silicon Macs, macOS 14 or later. Signed and notarized by Apple.

## Download and install

1. Click **Download for Mac** above, or open the [latest release](../../releases/latest) and under Assets click "Download for Mac (Apple Silicon)". The checksum files are optional.
2. Double-click the ZIP to unzip it and drag **Live AI Usage Widget** into Applications.
3. Open it. The setup window appears; follow its Setup help steps.

The app has no Dock icon. It lives in the menu bar (a ring with a pulse line): one line per account (Claude Code, ChatGPT Codex), then Settings, Check now and Quit. To update later, quit it from that menu, replace it in Applications and reopen it; your settings are kept.

## Setup and settings

**Setup help** (hides itself once both steps are done; the Setup help button brings it back)
1. Connect Claude Code, ChatGPT Codex or both.
2. Add the widget to your desktop: right-click an empty spot on the desktop, choose Edit Widgets, search for Live AI Usage Widget, pick a size and drag it on. macOS doesn't let apps place widgets themselves. Show me how walks through it, and the step turns green once a widget is placed.
**General.** Open at login, on by default.

**Accounts.** One line each for Claude Code and ChatGPT Codex, with one button that always says what it will do: Install, Connect, Connected (hover to Disconnect), or Sign in, Update, Finish setup or Try again when something needs attention. No Terminal needed. On first launch, tools that are already installed and signed in connect on their own. Disconnect only hides that account; the tool stays signed in.

**Appearance.** Style: Clean (default), Solar or Trends. Date format: US or European. Usage colors on or off, with three color bands you can recolor and re-threshold (30% or more remaining, 11–29%, 10% or less by default).

**Updates.** Check every N minutes: 5 by default, any value from 1 to 1,440. After a failed check the app waits at least 15 minutes before trying again. Check now in the menu bar checks immediately.

**Small widget readings.** Choose which readings the small widget shows (up to five). Medium and large show every reading.

Save settings applies changes. You can close the window at any time; the widget keeps updating while the app runs.

## What it shows

- Remaining percentage for each limit your plan exposes: Claude Code's five-hour, weekly and any model-specific weekly windows; ChatGPT Codex five-hour and weekly. ChatGPT Codex here means Codex coding allowances, not other ChatGPT products or API billing.
- When each limit resets, and when it was last updated. Readings fade as they age and failures show their date.
- Trends style adds a six-hour history of how fast each limit is being used. Gaps are drawn flat; nothing is invented.

## Requirements

- Apple Silicon Mac running macOS 14 or later. Intel Macs are not supported.
- Claude Code 2.1.301 or newer (`claude update`) and/or ChatGPT Codex (OpenAI's official Codex command-line tool), installed and signed into **your** account. Your plan must expose usage limits through that tool. API-key-only accounts are not supported.
- Nothing else. Python and developer tools are only needed to build from source.

No provider tools, credentials or private signing material are included.

## Known limits

Tested on two Apple Silicon Macs with real Claude Code and ChatGPT Codex accounts. Not yet tested: installing as a brand-new macOS user, reboots and sleep over several days, sign-ins renewing on their own over time, and revoked sign-ins. See [release checks](docs/RELEASE-CHECKLIST.md).

## Build and test

From this folder, not a parent project:

```sh
bash scripts/test.sh
python3 scripts/build.py
```

This produces a **compile-only** app in `build/Live AI Usage Widget.app`. It is not a signed installer. Nothing is installed, launched, registered at login or stopped by these commands.

A maintainer with their own correctly configured signing identity can build using:

```sh
python3 scripts/build.py --team-id YOURTEAMID --signing-identity 'Developer ID Application: YOUR NAME (YOURTEAMID)' --bundle-id com.yourcompany.aiusagewidget
```

Replace the example values. Configure the app group to match `TEAMID.BUNDLEID` in both targets and verify Apple's current signing/provisioning requirements. The script only applies supplied signing settings; it does not create accounts, entitlements or profiles. See [release checks](docs/RELEASE-CHECKLIST.md).

## Set up your accounts

1. In Settings, click Install beside Claude Code or ChatGPT Codex if it isn't on your Mac yet. It downloads the official tool in the background (Anthropic's installer, or OpenAI's signed Codex release for Apple Silicon).
2. Click Connect. If you aren't signed in, your browser opens so you can sign in to your own account. The app never sees your password. If the browser doesn't open, the button becomes Open sign-in page.
3. The button shows Connecting… until your first reading arrives, then Connected. For Claude Code it also answers the one-time "trust this folder" question, only for the app's own empty working folder.

Each tool keeps and renews its own sign-in; the app only asks it for the numbers.

Before changing accounts, Disconnect that account. This clears its widget history. Then sign into the new account and Connect again. Account changes made outside this workflow cannot be reliably detected because the collector intentionally does not retain account identities.

## Privacy and uninstall

Only percentages, reset times, observation/failure timestamps and a bounded six-hour graph history are retained. The app uses provider-owned login; it never opens credential files, collects conversations, reads browser cookies or sends telemetry. Provider CLIs themselves communicate with their services under their own policies.

Private collection state is stored under `~/Library/Application Support/BUNDLEID/`. Shared widget state and settings live in the signing team's app-group container. Source, attempt, publication and repaint times are different; see [architecture](docs/ARCHITECTURE.md).

To uninstall: turn off Open at login, choose Quit from the menu bar icon, remove its desktop widget, and move the app to Trash. Optionally remove its own Application Support folder and app-group container after verifying their exact identifiers. Do not delete provider credential stores or uninstall their tools unless you separately want that. No independent LaunchAgent is installed.

## License

This is independent software, not an Anthropic or OpenAI product. Provider names identify compatibility only.

Released under the [MIT License](LICENSE). See [third-party notices](THIRD-PARTY-NOTICES.md).

