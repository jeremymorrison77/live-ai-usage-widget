# Maintainer handoff

Current version: **0.3.1 beta (build 5), Apple Silicon, macOS 14+**, published as a GitHub prerelease. This repository is the whole project; it has no parent workspace.

## Current state

- Name: Live AI Usage Widget. Bundle identifier `com.liveaiusagewidget.app`, widget `com.liveaiusagewidget.app.widget`, app group `TEAMID.com.liveaiusagewidget.app`, link scheme `live-ai-usage-widget://`.
- The app opens one setup window (Get started steps, hidden once all are done with a Setup help link to show them, accounts, appearance, small-widget readings, preview). There is no separate preview window. Clean is the default style.
- Tests, compile-only build, source export and CI pass. 0.3.1 is notarized (submission `6fc9f8c5-140e-41b4-8821-39b103f9a8f3`), app ZIP SHA-256 `33da57f2aa4a68d177b928875ab5f55049e86e30ec202b8317006cc9f6f579d4`.
- README pictures in `docs/images/` are drawn offscreen from the app's real views with sample data, then stripped of metadata. `scripts/package.py` refuses PNGs that carry metadata.

Read `docs/VALIDATION.md` for dated evidence and `docs/RELEASE-CHECKLIST.md` for what is still untested.

## Releasing a new version

1. Bump `CFBundleShortVersionString`/`CFBundleVersion` in `scripts/build.py`, the version in `Helper/Reader.swift` client info and the archive name in `scripts/package.py`. Add a CHANGELOG entry.
2. `bash scripts/test.sh`, then a signed build: `python3 scripts/build.py --team-id TEAMID --signing-identity IDENTITY`.
3. `python3 scripts/release.py --notary-profile PROFILE` (resume an uncertain submission with `--submission-id`; never resubmit blindly), then `python3 scripts/package.py`.
4. Push, wait for CI, then create a GitHub prerelease with the app ZIP, source ZIP and both `.sha256` files. Download them back and verify the checksums.

Keep commits on the GitHub noreply address. Never add credentials, account screenshots or personal paths.
