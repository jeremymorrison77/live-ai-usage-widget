# Release acceptance

Version 1.1.8. A signed, notarized Apple Silicon ZIP is prepared. Notarization establishes Apple's distribution check, not compatibility with every account or Mac.

## Verified locally

- [x] Product name Live AI Usage Widget; MIT license included.
- [x] Native Swift collector; no runtime Python dependency or bundled provider binaries.
- [x] Clean and Solar, small/medium/large layouts, account selection and small-widget metric selection.
- [x] Reader protocol/parser, timeout, privacy filtering, retry/backoff, failure retention and history tests.
- [x] Signed companion and WidgetKit extension, hardened runtime, matching app groups.
- [x] Host app-group read/write self-check; real Claude Code and ChatGPT Codex readings on both test Macs. The second Mac's desktop displayed both providers.
- [x] Settings gear opens Settings; account indicators and linked percent inputs checked in the running app.
- [x] Apple notarization Accepted, ticket stapled, signature verification and Gatekeeper acceptance.
- [x] Versioned app ZIP and SHA-256 checksum; installation/update/uninstall instructions.

## Publication and follow-up checks

- [x] Review the exact allowlisted source and app artifacts before upload.
- [x] Create the repository (live-ai-usage-widget, public since 10/17/2026), run its CI and enable private vulnerability reporting. Never publish a containing private project or its history.
- [x] Confirm desktop widget gallery registration and actual timeline rendering on a separate Mac (small widget, 10/17/2026). Medium/large actual desktop placement still needs review.
- [ ] Test a downloaded archive on a separate Apple Silicon Mac or fresh macOS user: Claude Code alone, ChatGPT Codex alone, both and neither; missing tools and first-run sign-in.
- [ ] Verify US/EU dates, all styles/sizes, color controls, macOS full-color/tinted appearance and accessibility in installed widgets.
- [ ] Test login-item enable/disable, reboot, sleep/wake, app relaunch, account switching and uninstall.
- [ ] Observe natural credential renewal with fresh source timestamps, revoked authorization and network recovery. Existing-account success is not proof of renewal.
- [ ] Record a supported provider-version/account-plan matrix. Intel is not supported.

Keep these limits explicit in release notes and the README. Do not describe the app as universally installable or permanently authenticated.

## Maintainer distribution commands

Build with your own Developer ID identity and team (see README), then:

```sh
python3 scripts/release.py --notary-profile YOUR_SAVED_KEYCHAIN_PROFILE
python3 scripts/package.py
```

The release command submits to Apple, records the submission ID, waits, staples and verifies. If interrupted, inspect Apple's status and use `--submission-id ID` to resume the same submission. Never automatically resubmit an uncertain upload. Credentials stay in Keychain; do not put them in source, logs or CI variables unless separately reviewed.
