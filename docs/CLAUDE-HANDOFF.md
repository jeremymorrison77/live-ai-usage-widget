# Maintainer handoff

Current version: **1.1.2 (build 23), Apple Silicon, macOS 14+**, published as a full GitHub release in the public repository. This repository is the whole project; it has no parent workspace.

## Current state

- Name: Live AI Usage Widget. Bundle identifier `com.liveaiusagewidget.app`, widget `com.liveaiusagewidget.app.widget`, app group `TEAMID.com.liveaiusagewidget.app`, link scheme `live-ai-usage-widget://`.
- The app is a menu bar app (no Dock icon): one iconned line per account, then Settings, Check now and Quit. It opens one setup window (Setup help steps, hidden once all are done with a Setup help link to show them, accounts, appearance, updates interval, small-widget readings; Setup help and Save settings centered at the bottom). There is no separate preview window. Connecting needs no Terminal: background install, browser sign-in, and automatic trust of the app's own probe folder. Clean is the default style.
- Tests, compile-only build, source export and CI pass. 1.1.2 is notarized (submission `4edc3bd6-395d-4a6b-b96e-0112f1e21bf0`), app ZIP SHA-256 `8c0e92508d036b0337085acc4703fe4793d27714a1baa49b11057e63934d8191`.
- The README picture `docs/images/overview.png` is drawn by `bash scripts/render_overview.sh` from the app's real views with sample data, then stripped of metadata. `scripts/package.py` refuses PNGs that carry metadata.

Read `docs/VALIDATION.md` for dated evidence and `docs/RELEASE-CHECKLIST.md` for what is still untested.

## Releasing a new version

1. Bump `CFBundleShortVersionString`/`CFBundleVersion` in `scripts/build.py`, the version in `Helper/Reader.swift` client info and the archive name in `scripts/package.py`. Add a CHANGELOG entry.
2. `bash scripts/test.sh`, then a signed build: `python3 scripts/build.py --team-id TEAMID --signing-identity IDENTITY`.
3. `python3 scripts/release.py --notary-profile PROFILE` (resume an uncertain submission with `--submission-id`; never resubmit blindly), then `python3 scripts/package.py`.
4. Push, wait for CI, then create a GitHub prerelease with the app ZIP, source ZIP and both `.sha256` files. Download them back and verify the checksums. Give the app ZIP the asset label "Download for Mac (Apple Silicon) - Live AI Usage Widget X.Y.Z" and update the README Download for Mac link to the new file name.

Keep commits on the GitHub noreply address. Never add credentials, account screenshots or personal paths.

## 1.1.2 (10/18/2026)

Troubleshooting section with Save report… (`Diagnostics`): private activity log in ~/Library/Logs/Live AI Usage Widget/activity.log, past three days only, capped at 256 KB, only changes logged, personal details (home folder, emails, links, long tokens) stripped. The owner rejected a "Scroll down" hint and fade for the settings window; do not re-add it.

## 1.1.1 (10/18/2026)

From a friend's first install: Claude Code sign-in printed "Paste code here if prompted" and the app stopped the tool, so Authorize hit a refused localhost page; the tool now runs until sign-in ends (10 minutes). Opened from Downloads (App Translocation), the app offers to move itself into Applications (`Mover`). Update check against the latest GitHub release with one-click install (`Updater`): checksum, notarization and same-team signature required; a helper swaps the app after it quits. Claude Code lookup also covers npm, nvm, Bun and Volta. The Claude desktop app's private Claude Code copy is not usable by other apps.

## 1.1.0 (10/18/2026)

Released from the owner's testing session. Accounts are one line each (Claude Code, ChatGPT Codex) with a single stateful button (Install, Connect, Connecting…, Connected/Disconnect, Sign in, Update, Finish setup, Try again, Open sign-in page). One name per account everywhere via `WidgetStatus.name`. First launch auto-connects signed-in tools; Open at login on by default. Newly connected accounts show Loading… rows on the widget at once. Limits a plan lacks are listed grayed as "Not included in your plan" (`WidgetStatus.notInPlan`; ChatGPT Pro has no 5-hour limit, only Claude Max and Premium seats have weekly Fable, per official plan pages 10/18/2026). Settings window is resizable and remembers its frame; background checks are silent. Notary profile on the owner's Mac: `bitemark-notarytool`.
