# Maintainer handoff

Current version: **1.0.1 (build 14), Apple Silicon, macOS 14+**, published as a full GitHub release in the public repository. This repository is the whole project; it has no parent workspace.

## Current state

- Name: Live AI Usage Widget. Bundle identifier `com.liveaiusagewidget.app`, widget `com.liveaiusagewidget.app.widget`, app group `TEAMID.com.liveaiusagewidget.app`, link scheme `live-ai-usage-widget://`.
- The app is a menu bar app (no Dock icon) with Settings, Check now and Quit. It opens one setup window (Get started steps, hidden once all are done with a Setup help link to show them, accounts, appearance, updates interval, small-widget readings; Setup help and Save settings centered at the bottom). There is no separate preview window. Connecting needs no Terminal: background install, browser sign-in, and automatic trust of the app's own probe folder. Clean is the default style.
- Tests, compile-only build, source export and CI pass. 1.0.1 is notarized (submission `8da8a2bc-259e-4e85-8d49-c1059463c571`), app ZIP SHA-256 `05d8853e4fc1a605d9c6931434a731af71d48b350873a2460287f5b0594a1d36`.
- README pictures in `docs/images/` are drawn offscreen from the app's real views with sample data, then stripped of metadata. `scripts/package.py` refuses PNGs that carry metadata.

Read `docs/VALIDATION.md` for dated evidence and `docs/RELEASE-CHECKLIST.md` for what is still untested.

## Releasing a new version

1. Bump `CFBundleShortVersionString`/`CFBundleVersion` in `scripts/build.py`, the version in `Helper/Reader.swift` client info and the archive name in `scripts/package.py`. Add a CHANGELOG entry.
2. `bash scripts/test.sh`, then a signed build: `python3 scripts/build.py --team-id TEAMID --signing-identity IDENTITY`.
3. `python3 scripts/release.py --notary-profile PROFILE` (resume an uncertain submission with `--submission-id`; never resubmit blindly), then `python3 scripts/package.py`.
4. Push, wait for CI, then create a GitHub prerelease with the app ZIP, source ZIP and both `.sha256` files. Download them back and verify the checksums. Give the app ZIP the asset label "Download for Mac (Apple Silicon) - Live AI Usage Widget X.Y.Z" and update the README Download for Mac link to the new file name.

Keep commits on the GitHub noreply address. Never add credentials, account screenshots or personal paths.
