# Maintainer handoff

Current version: **1.0.1 (build 14), Apple Silicon, macOS 14+**, published as a full GitHub release in the public repository. This repository is the whole project; it has no parent workspace.

## Current state

- Name: Live AI Usage Widget. Bundle identifier `com.liveaiusagewidget.app`, widget `com.liveaiusagewidget.app.widget`, app group `TEAMID.com.liveaiusagewidget.app`, link scheme `live-ai-usage-widget://`.
- The app is a menu bar app (no Dock icon) with Settings, Check now and Quit. It opens one setup window (Setup help steps, hidden once all are done with a Setup help link to show them, accounts, appearance, updates interval, small-widget readings; Setup help and Save settings centered at the bottom). There is no separate preview window. Connecting needs no Terminal: background install, browser sign-in, and automatic trust of the app's own probe folder. Clean is the default style.
- Tests, compile-only build, source export and CI pass. 1.0.1 is notarized (submission `8da8a2bc-259e-4e85-8d49-c1059463c571`), app ZIP SHA-256 `05d8853e4fc1a605d9c6931434a731af71d48b350873a2460287f5b0594a1d36`.
- README pictures in `docs/images/` are drawn offscreen from the app's real views with sample data, then stripped of metadata. `scripts/package.py` refuses PNGs that carry metadata.

Read `docs/VALIDATION.md` for dated evidence and `docs/RELEASE-CHECKLIST.md` for what is still untested.

## Releasing a new version

1. Bump `CFBundleShortVersionString`/`CFBundleVersion` in `scripts/build.py`, the version in `Helper/Reader.swift` client info and the archive name in `scripts/package.py`. Add a CHANGELOG entry.
2. `bash scripts/test.sh`, then a signed build: `python3 scripts/build.py --team-id TEAMID --signing-identity IDENTITY`.
3. `python3 scripts/release.py --notary-profile PROFILE` (resume an uncertain submission with `--submission-id`; never resubmit blindly), then `python3 scripts/package.py`.
4. Push, wait for CI, then create a GitHub prerelease with the app ZIP, source ZIP and both `.sha256` files. Download them back and verify the checksums. Give the app ZIP the asset label "Download for Mac (Apple Silicon) - Live AI Usage Widget X.Y.Z" and update the README Download for Mac link to the new file name.

Keep commits on the GitHub noreply address. Never add credentials, account screenshots or personal paths.

## Unreleased work since 1.0.1 (10/18/2026)

Built, signed (not notarized) and installed on the owner's Mac for testing; committed locally, not pushed:
- Accounts rows: name · Installed/Not installed · one button (Install Claude Code / Install Codex → Connect → Connected; hover shows Disconnect, which only hides the account). Connect installs if needed, checks sign-in, opens the browser if not signed in, then checks the connection. The old Connect sheet is gone.
- First launch auto-detects installed, signed-in tools and connects them (`autoDetected` setting). Open at login is a General toggle, on by default. Get started has two steps (connect accounts, add widget). Window title: Live AI Usage Widget Settings.
- Menu bar: one line per account with an icon (green check when connected), then Settings, Check now, Quit, all with icons so text aligns. No disconnect in the menu.
- Fixed: `claude auth status` output in a terminal uses cursor codes; it is now stripped before reading `loggedIn`.
- 10/18/2026 fixes from owner testing: spinner inside the working account's button; steady Connecting… until the reading arrives; disconnecting one account keeps the other; no extra lines under account rows (problems and the sign-in link are button states; no Installed text); quiet background checks with a fixed message line; nothing focused on open; resizable settings window that remembers its size; typed numbers kept on Save. One name per account everywhere: Claude Code and ChatGPT Codex (`WidgetStatus.name`). Small widget rows use 10 pt so the full names fit.
- README picture `docs/images/overview.png` still shows the old window and names; redraw it before the next release.
- Owner may still have more issues to discuss. Builds use `CFBundleVersion` 20; bump the version, notarize and release only when the owner says.

