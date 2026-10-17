# Maintainer handoff

Current version: **0.3.1 beta (build 9), Apple Silicon, macOS 14+**, published as a GitHub prerelease. This repository is the whole project; it has no parent workspace.

## Current state

- Name: Live AI Usage Widget. Bundle identifier `com.liveaiusagewidget.app`, widget `com.liveaiusagewidget.app.widget`, app group `TEAMID.com.liveaiusagewidget.app`, link scheme `live-ai-usage-widget://`.
- The app opens one setup window (Get started steps, hidden once all are done with a Setup help link to show them, accounts, appearance, updates interval, small-widget readings; Setup help and Save settings centered at the bottom). There is no separate preview window. Clean is the default style.
- Tests, compile-only build, source export and CI pass. 0.3.1 is notarized (submission `7be4e79c-d04d-4a75-afbd-4d679b5c944c`), app ZIP SHA-256 `d331e2ca5f086d2d19b17d771bac9c87e07a4f833b4fdb5a8c75cee825633c88`.
- README pictures in `docs/images/` are drawn offscreen from the app's real views with sample data, then stripped of metadata. `scripts/package.py` refuses PNGs that carry metadata.

Read `docs/VALIDATION.md` for dated evidence and `docs/RELEASE-CHECKLIST.md` for what is still untested.

## Releasing a new version

1. Bump `CFBundleShortVersionString`/`CFBundleVersion` in `scripts/build.py`, the version in `Helper/Reader.swift` client info and the archive name in `scripts/package.py`. Add a CHANGELOG entry.
2. `bash scripts/test.sh`, then a signed build: `python3 scripts/build.py --team-id TEAMID --signing-identity IDENTITY`.
3. `python3 scripts/release.py --notary-profile PROFILE` (resume an uncertain submission with `--submission-id`; never resubmit blindly), then `python3 scripts/package.py`.
4. Push, wait for CI, then create a GitHub prerelease with the app ZIP, source ZIP and both `.sha256` files. Download them back and verify the checksums.

Keep commits on the GitHub noreply address. Never add credentials, account screenshots or personal paths.
