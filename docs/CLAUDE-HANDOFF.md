# Final review and release handoff

Current candidate: **0.2.1 beta, Apple Silicon, macOS 14+**. Signed/notarized app build 3. This package contains public source only; its containing workspace, private history and runtime state are not part of the product.

## Verified state

- 18 Python reference tests, native Swift reader/history/store checks and signed app/extension build passed. Native app collection does not require Python.
- Separate-Mac install, gallery registration for all sizes, official Claude setup, existing ChatGPT sign-in, both providers' real usage, and small desktop timeline repaint passed.
- The reader includes five-hour and weekly windows when returned; absent windows are omitted regardless of plan name. Synthetic previews are not live account evidence.
- Claude startup cancels only the exact optional auto-mode migration prompt; other trust/login/permission prompts are surfaced. Chrome integration is disabled. No Chrome-data permission was granted.
- Apple Accepted submission: `0c827eff-8669-421a-b6da-ae26acabc55e`.
- App archive: `Live-Usage-Widget-0.2.1-macOS-arm64.zip`.
- App SHA-256: `d2dcf755b51b506acdb0ea811276ad28c0a4d65c46c4de696a471c3e902dee94`.

Read `docs/VALIDATION.md` for dated evidence and limits. Existing-account reads do not prove natural renewal.

## Final checks

1. Review every file in `release-files.json`, the workflow, license, README and security policy. Export only that manifest into a new repository with fresh history. Never initialize/push a containing private workspace.
2. Run `bash scripts/test.sh`. Compile with `python3 scripts/build.py` in an isolated verification directory; that unsigned compile must not overwrite the signed candidate used for distribution. Run `python3 scripts/package.py`; extract the source ZIP and compare each entry with its manifest source. Scan source and binary artifacts for personal paths, credentials and private state.
3. Validate the exact signed ZIP independently: checksum, extract, `codesign --verify --deep --strict`, `xcrun stapler validate`, and `spctl --assess --type execute --verbose=2`. If executable source changes, rebuild, increment version/build as appropriate and notarize the new artifact; never reuse an old ticket/checksum claim. Resume uncertain notarization by existing submission ID.
4. Complete `docs/RELEASE-CHECKLIST.md`: fresh-user/browser-downloaded installation, provider combinations, medium/large desktop placement, settings, accessibility and login/relaunch recovery. Reboot, account revocation, sign-out or other disruptive tests need a separately agreed time; do not interrupt unrelated apps. Natural renewal needs a genuine expiry event and fresh source evidence. Do not accelerate it by editing tokens.
5. Fix reproducible blockers. If timed/user-present checks remain, record them explicitly and publish only as a **GitHub prerelease**, never as fully stable or universally compatible. Unresolved privacy/security faults, invalid signing, incorrect readings, failing tests or failed CI block publication.
6. For an owner-authorized publication, create the intended standalone repository, push only sanitized source, enable private vulnerability reporting when available, and wait for CI. Publish tag `v0.2.1` as a prerelease (or the new corrected version), attaching the notarized arm64 app ZIP/checksum and final source ZIP/checksum. Release notes must explain prerequisites, setup and the remaining test limits. Verify the public download/checksum afterward. Report the repository and release URLs.

## Copy-paste continuation

> Finish the Live Usage Widget public beta release. Work only in this standalone package; read this handoff, README, ARCHITECTURE, VALIDATION and RELEASE-CHECKLIST first. Audit the exact source and signed artifacts, run tests and isolated build checks, fix blockers, and publish to the owner-authorized GitHub destination only after validation and CI pass. Use a prerelease while listed lifecycle/renewal checks remain unverified. Preserve all approved designs, account selection, optional five-hour/weekly readings, real-data Trends, flat missing-data lines, colors, date formats, retries and honest failure timestamps. Never invent usage, read/copy credentials or conversation logs, upload private parent history, or stop processes by name. No paid services, purchases or additional accounts are authorized. Stop for an actual security permission, destructive test, ambiguous existing repository or failing release gate. Keep temporary copies until changes are merged into the retained source, then clean disposable verification files. Report what passed, what remains, and the final public URLs.
