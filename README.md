# Live AI Usage Widget

A macOS desktop widget that shows how much of your Claude Code and ChatGPT/Codex coding allowance is left. Small, medium and large widgets come in Clean (default), Solar and Trends styles. Accounts and data stay on your own Mac.

<p align="center">
  <img src="docs/images/clean-small.png" alt="Small widget, Clean style" width="200">
  <img src="docs/images/clean-medium.png" alt="Medium widget, Clean style" width="380">
</p>
<p align="center">
  <img src="docs/images/clean-large.png" alt="Large widget, Clean style" width="380">
</p>

| Solar | Trends |
| --- | --- |
| <img src="docs/images/solar-medium.png" alt="Medium widget, Solar style" width="380"> | <img src="docs/images/trends-medium.png" alt="Medium widget, Trends style" width="380"> |

**Setup window**

<p align="center"><img src="docs/images/settings.png" alt="Setup and settings window" width="420"></p>

Pictures are drawn from the app's own views with made-up sample readings, not a real account.

**0.3.1 beta.** Apple Silicon, macOS 14 or later. Signed download packaging is prepared; see the [validation record](docs/VALIDATION.md) for verified checks and remaining independent-Mac acceptance. This is not yet a broadly tested stable release.

## What works in this source

- Claude, ChatGPT/Codex, or both, with separate provider selection and your own official CLI sign-in.
- Actual available limits; model-specific Claude windows are optional. ChatGPT here means Codex coding allowances, not all ChatGPT products or API billing.
- Remaining percentages and a six-hour history of observed consumption rate; no invented activity. Missing coverage is a flat placeholder, distinguished in hover/accessibility text.
- Whole traces use the same color as their percentages. Small widgets use extra space for reset information when fewer metrics are present.
- US/European dates, color swatches and thresholds, muted refresh/settings links, optional opening at login.
- Five-minute collection target while the app is running; failed providers wait fifteen minutes. Manual refresh respects this backoff. WidgetKit decides actual repaint timing.
- Source timestamps remain unchanged after failures. Failure dates appear in the footer; cached values fade as they age.

Choose Clean bars, Solar rings or Trends history. Settings include per-metric small-widget selection and a Sign in button that opens the official tool in Terminal. There is no name/logo header or logo upload.

## Requirements

- Apple Silicon Mac running macOS 14 or later. Intel builds are a build option but **not tested or supported for this preview**.
- Apple command-line development tools for source builds.
- No Python or development tools are needed to run the packaged app. Python 3.10+ and Xcode command-line tools are used only for source builds and tests.
- Claude Code 2.1.301 or newer (`claude update`), and/or the official Codex CLI installed and signed into **your** account. A plan must expose usage limits through that tool. API-key-only accounts are not claimed to work.
- To use the desktop widget from your own build: your own matching Apple signing team, certificate and app-group entitlement. A compile-only build does not establish that the widget can register or share storage.

No provider binaries, Python runtime, credentials or private signing material are included. The distributed app contains the normal public Developer ID signature.

## Install the packaged beta

1. Download the macOS arm64 ZIP from a published GitHub release and compare its SHA-256 checksum with the accompanying checksum file.
2. Unzip it and drag **Live AI Usage Widget.app** into Applications. Open it normally. A notarized build should pass macOS Gatekeeper; do not disable security checks.
3. The setup window opens. Follow its three Get started steps (they hide once all are done; Setup help at the bottom brings them back): connect your accounts, add the widget to your desktop (right-click the desktop → Edit Widgets → search Live AI Usage), and optionally turn on Open at login.
4. For updates, quit this app normally, replace it in Applications, and reopen it. Settings are retained. There is no automatic updater.

Version 0.2.1 installation, launch, settings, all three gallery previews, official Claude sign-in, real readings and small desktop-widget repaint passed on a second Apple Silicon Mac. Browser-downloaded quarantine acceptance, reboot and natural credential renewal remain unverified.

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

1. Install the provider's official command-line tool using its own instructions. Finish its first-run setup in Terminal.
2. Run `claude auth login` or `codex login` and complete the provider-owned authentication. Never paste credentials into this app.
3. Open a properly signed build. In the setup window select the providers you want and save. Connect → Sign in launches the official login command in Terminal; Check connection reads usage after sign-in.
4. Refresh. “Connected” appears only after a fresh successful usage reading. Authentication or usage rate limits can delay the next attempt by fifteen minutes.
5. Add Live AI Usage Widget through macOS's widget gallery (the window's Show me how button explains it; macOS doesn't let apps place widgets themselves). Enable “Open at login” if wanted. Keep the app running; closing its window is fine, quitting stops collection. Reopen the window from the Dock, with Command-comma, or with the widget's gear button.

Before changing accounts, turn off that provider and save. This clears widget history and invalidates the collector cache. Then sign into the new account, enable the provider and save again. Account changes made outside this workflow cannot be reliably detected because the collector intentionally does not retain account identities.

## Privacy and uninstall

Only percentages, reset times, observation/failure timestamps and a bounded six-hour graph history are retained. The app uses provider-owned login; it never opens credential files, collects conversations, reads browser cookies or sends telemetry. Provider CLIs themselves communicate with their services under their own policies.

Private collection state is stored under `~/Library/Application Support/BUNDLEID/`. Shared widget state and settings live in the signing team's app-group container. Source, attempt, publication and repaint times are different; see [architecture](docs/ARCHITECTURE.md).

To uninstall: disable “Open at login,” quit this app normally, remove its desktop widget, and move the app to Trash. Optionally remove its own Application Support folder and app-group container after verifying their exact identifiers. Do not delete provider credential stores or uninstall their tools unless you separately want that. No independent LaunchAgent is installed.

## Status and license

See [release checks](docs/RELEASE-CHECKLIST.md) for what is verified versus pending. This is independent software, not an Anthropic or OpenAI product. Provider names identify compatibility only.

Released under the [MIT License](LICENSE). See [third-party notices](THIRD-PARTY-NOTICES.md).

Claude first-run setup: after sign-in, use **Finish Claude setup** in the connection sheet to approve the widget working folder in Terminal. Close that Terminal window, then choose **Check connection**. Older CLI versions are reported as needing an update, not as network timeouts.
