# Maintainer handoff

Current version: **1.1.6 (build 27), Apple Silicon, macOS 14+**, published as a full GitHub release in the public repository. This repository is the whole project; it has no parent workspace.

## Current state

- Name: Live AI Usage Widget. Bundle identifier `com.liveaiusagewidget.app`, widget `com.liveaiusagewidget.app.widget`, app group `TEAMID.com.liveaiusagewidget.app`, link scheme `live-ai-usage-widget://`.
- The app is a menu bar app (no Dock icon): one iconned line per account, then Settings, Check usage now and Quit. It opens one setup window (Setup help steps, hidden once all are done with a Setup help link to show them, accounts, appearance, updates interval, small-widget readings; settings apply as they change (no Save button); Setup help toggle at the bottom once set up). There is no separate preview window. Connecting needs no Terminal: background install, browser sign-in, and automatic trust of the app's own probe folder. Clean is the default style.
- Tests, compile-only build, source export and CI pass. 1.1.6 is notarized (submission `41b0b099-fc8c-4739-b852-d349c158a504`), app ZIP SHA-256 `ef0a13c1dd3eac1729e8d36785c2e587616a079ae13a5dc9495ace96d87d4278`.
- The README picture `docs/images/overview.png` is drawn by `bash scripts/render_overview.sh` from the app's real views with sample data, then stripped of metadata. `scripts/package.py` refuses PNGs that carry metadata.

Read `docs/VALIDATION.md` for dated evidence and `docs/RELEASE-CHECKLIST.md` for what is still untested.

## Releasing a new version

1. Bump `CFBundleShortVersionString`/`CFBundleVersion` in `scripts/build.py`, the version in `Helper/Reader.swift` client info and the archive name in `scripts/package.py`. Add a CHANGELOG entry.
2. `bash scripts/test.sh`, then a signed build: `python3 scripts/build.py --team-id TEAMID --signing-identity IDENTITY`.
3. `python3 scripts/release.py --notary-profile PROFILE` (resume an uncertain submission with `--submission-id`; never resubmit blindly), then `python3 scripts/package.py`.
4. Push, wait for CI, then create a GitHub prerelease with the app ZIP, source ZIP and both `.sha256` files. Download them back and verify the checksums. Give the app ZIP the asset label "Download for Mac (Apple Silicon) - Live AI Usage Widget X.Y.Z" and update the README Download for Mac link to the new file name.

Keep commits on the GitHub noreply address. Never add credentials, account screenshots or personal paths.

## 1.1.6 (10/18/2026)

After a self-update the old widget extension kept running from the Trash copy, so the widget ran old code; `Updater.stopWidgetHelpers` now stops processes under the old bundle's PlugIns folder before quitting. Settings window is kept at alpha 0 until the launch decides whether to show it (no flash at login or after updates); a `reopenSettingsAfterUpdate` default brings it back if it was open. Refresh plans 3 spinner entries and fades in 0.25 s.

## 1.1.5 (10/18/2026)

`UsageReader.find` falls back to the person's login shell (`$SHELL -ilc "command -v NAME"`, 5-second limit, remembered for a minute) when the usual folders miss. Screens use `find(askShell: false)` plus the remembered answer; the app refreshes it in the background each minute. `installNow` re-checks everywhere first and never installs a second copy (owner's rule).

## 1.1.4 (10/18/2026)

Trends style removed. Settings apply as they change (no Save button). The widget's refresh button is an App Intent (`CheckUsageIntent`); `scripts/build.py` produces its Metadata.appintents with `appintentsmetadataprocessor`. The app watches the group container for `check-request`. Widget findings, confirmed by filming the desktop: Mac pre-renders every timeline entry before showing the first (so only 3 one-second spinner entries are planned at a time), and it animates changes between reloads but not between planned entries (so bars fade on the click reload, reset while invisible, and grow on the reload that brings the reading). The app reloads widgets only when readings change (background reload budget). Rate limits show a countdown ("Too many refreshes. Waiting mm:ss to try again."; two lines on small) instead of a failure; the 15-minute wait is the app's own. `invalidatableContent` made bars pulse; do not re-add.

## 1.1.3 (10/18/2026)

Settings opened slightly scrolled down because macOS gave the first text box (30%) the cursor and scrolled to it. Number boxes are now `NumberField`: plain value until clicked, then a text box. Clearing focus afterwards was not enough.

## 1.1.2 (10/18/2026)

Troubleshooting section with Save report… (`Diagnostics`): private activity log in ~/Library/Logs/Live AI Usage Widget/activity.log, past three days only, capped at 256 KB, only changes logged, personal details (home folder, emails, links, long tokens) stripped. The owner rejected a "Scroll down" hint and fade for the settings window; do not re-add it.

## 1.1.1 (10/18/2026)

From a friend's first install: Claude Code sign-in printed "Paste code here if prompted" and the app stopped the tool, so Authorize hit a refused localhost page; the tool now runs until sign-in ends (10 minutes). Opened from Downloads (App Translocation), the app offers to move itself into Applications (`Mover`). Update check against the latest GitHub release with one-click install (`Updater`): checksum, notarization and same-team signature required; a helper swaps the app after it quits. Claude Code lookup also covers npm, nvm, Bun and Volta. The Claude desktop app's private Claude Code copy is not usable by other apps.

## 1.1.0 (10/18/2026)

Released from the owner's testing session. Accounts are one line each (Claude Code, ChatGPT Codex) with a single stateful button (Install, Connect, Connecting…, Connected/Disconnect, Sign in, Update, Finish setup, Try again, Open sign-in page). One name per account everywhere via `WidgetStatus.name`. First launch auto-connects signed-in tools; Open at login on by default. Newly connected accounts show Loading… rows on the widget at once. Limits a plan lacks are listed grayed as "Not included in your plan" (`WidgetStatus.notInPlan`; ChatGPT Pro has no 5-hour limit, only Claude Max and Premium seats have weekly Fable, per official plan pages 10/18/2026). Settings window is resizable and remembers its frame; background checks are silent. Notary profile on the owner's Mac: `bitemark-notarytool`.
