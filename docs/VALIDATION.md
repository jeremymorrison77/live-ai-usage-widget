# Validation record

## 1.0.0 (build 10) — 10/17/2026

Same app as 0.3.1 build 9 below with the version set to 1.0.0; re-signed and re-notarized (submission 0f38362b-858a-44d6-9b3e-06d62ba8d039 Accepted; app ZIP SHA-256 c9f9b66b046ee8e4c49e51138200128883eff2899b7a066d8466c5d60c9151df). Tests and stapled/Gatekeeper checks pass.

## 0.3.1 (build 9) — 10/17/2026

Get started hides once all three steps are done (Setup help button beside Save settings brings it back), Preview usage removed, gallery shows sample readings, adjustable check interval (default 5 minutes). Tests (including new interval checks), signed build and notarization pass (submission 7be4e79c-d04d-4a75-afbd-4d679b5c944c Accepted). App ZIP SHA-256: d331e2ca5f086d2d19b17d771bac9c87e07a4f833b4fdb5a8c75cee825633c88. Installed fresh on the development Mac with earlier settings cleared for a first-run walkthrough. Remaining limits match 0.3.0 below.

## 0.3.0 (build 4) — 10/17/2026

Rename and setup-window change. Python reference, Swift history/store and native reader tests pass; compile-only and signed builds pass. Apple notarization submission bbbafbb3-d476-4251-bedc-768648c2ebba Accepted; stapled, strict signature and Gatekeeper pass. App ZIP SHA-256: 39f5c583ffd08d1b59030b96c8855b3647ed8de93b0ce18e081ae739f82b7a3f. The signed app opened its setup window on launch on the development Mac. Not yet checked for 0.3.0: second-Mac install, widget placement detection on a real desktop, gear/refresh links with the window closed, and everything still listed in RELEASE-CHECKLIST. Entries below describe 0.2.x under the earlier name.

October 17, 2026, macOS Apple Silicon, 0.2.0 beta candidate:

- Companion and WidgetKit extension compile targeting macOS 14; both signed with Developer ID and hardened runtime.
- 18 Python reference tests pass. Native Swift reader tests pass: exact Codex bucket, invalid values, optional Claude model windows, timezone parsing, cursor redraw, stdio/PTY protocols, timeout, backoff, sanitized failures, recovery and disabled providers.
- Swift history/store assertions pass: actual rates, quiet intervals, duplicates, invalid inputs, resets, missing reset identity, long gaps, retention, bounded storage and failed-refresh persistence.
- Signed host app-group read/write self-check passes. Running companion shows fresh Claude and Codex readings from existing local accounts; Codex recovered after its retry interval. No sign-in was required for those reads. This does not establish a token-renewal event or independent-account onboarding.
- Running Settings screen inspected: equal-width green Connected buttons, provider checkboxes, centered percentage fields and linked thresholds. Entering 35% updates the middle upper limit to 34%; restored default 30%. Settings gear opens the correct window. Refresh respects the provider interval and does not force a network request on every click.
- Clean/Solar/Trends synthetic renders cover small, medium and large. Synthetic preview output is not real usage or installed WidgetKit evidence.
- The app extracted from the final ZIP also passes strict signature verification, stapled-ticket validation and Gatekeeper. Sandboxed signature verification produced a false failure; the unrestricted system check passes and extracted bytes match the original bundle.
- Apple submission 695d0de9-d7df-41c5-8e84-945365c56659 is Accepted. Staple/validate, strict signature verification and Gatekeeper pass (`Notarized Developer ID`). App ZIP and checksum are generated separately from source.
- Binary privacy scan found no personal home path, private workspace path or account email. The normal public signing certificate identifies the developer; no private signing keys or credential profiles are bundled.

The source export uses an explicit manifest and includes no account data, private project history or runtime state. The app uses the user's separately installed official provider tools. Python adapters remain reference/development code only; the distributed app uses Swift.

Not yet verified: independent-Mac downloaded installation, first-run provider setup on a fresh user, actual desktop WidgetKit timeline consumption/repaint, natural token renewal, reboot/login-item lifecycle, tinted-mode appearance and Intel support. CI is prepared but has not run on GitHub. See RELEASE-CHECKLIST.md; do not infer these outcomes from notarization or tests.

The 35-file source archive was extracted in an isolated folder with an empty HOME. Its tests, compile-only app/extension/icon build and re-export pass (Apple icon conversion required execution outside the sandbox). All code matches the reviewed source byte-for-byte. Documentation was updated after validation. Temporary extraction removed; this is build isolation, not a fresh macOS-user installation.

## Separate-Mac installation test — October 17, 2026

The exact 0.2.0 arm64 ZIP was copied to a second Apple Silicon Mac running a newer macOS release. SHA-256 matched the release artifact. Strict signature verification and Gatekeeper accepted it as Notarized Developer ID. Installed in Applications without overwriting another copy; the app-group read/write self-check passed. GUI launch and the settings gear worked. macOS registered the extension and its gallery rendered small, medium and large previews. No Python installation was needed. Temporary installer files were removed.

Claude Code 2.1.126 was present but its official status reported signed out. The app's read timed out; its failure date/time appeared correctly. No successful account reading or token renewal was established on this Mac. Codex was not present in the checked standard paths. Actual desktop placement/repaint remains unverified. This was a LAN-transferred artifact, not a browser download carrying quarantine; first-download acceptance remains separate. The installed app remains for follow-up testing.

Follow-up: official Claude sign-in completed on the separate Mac, with browser success and Terminal Login successful observed. The next native collection still timed out with no usage windows. Therefore first-run real-data acceptance remains failed; do not publish this candidate as fully validated. Authentication renewal remains untested.

Diagnosis: the test Mac had Claude 2.1.126, which rejected --safe-mode. Official update installed 2.1.302; startup then exposed the workspace trust prompt. Source now reports incompatible CLI options explicitly, supplies a user-driven Finish Claude setup flow, and allows an explicit post-setup connection check without waiting for earlier backoff. Signed compilation and reader regression tests pass. Replacement app installation, trusted-folder onboarding and live data remain pending. Existing release ZIP predates these corrections.

## 0.2.1 correction and separate-Mac live acceptance

October 17, 2026: exact widget probe-folder trust was approved by the tester. Claude 2.1.302 then presented an optional auto-mode migration question on startup. Cancelling with Escape preserved the explicit dontAsk mode and allowed /usage. The reader now cancels only this exact optional question once; unrelated trust, login and permission prompts still fail closed. Its CLI flags explicitly disable Chrome integration and optional settings. macOS had blocked an attempted Chrome-data access; that permission stayed OFF throughout successful collection.

18 Python reference tests, Swift history/store and native reader tests pass, including a PTY test requiring exactly Escape before producing usage and an unrelated trust-prompt rejection.

Signed 0.2.1 (build 3) notarization submission 0c827eff-8669-421a-b6da-ae26acabc55e was Accepted. Staple/validate, strict signature and Gatekeeper passed. App ZIP SHA-256: d2dcf755b51b506acdb0ea811276ad28c0a4d65c46c4de696a471c3e902dee94. The same checksum and Gatekeeper approval were verified on the second Mac before installation.

The app's GUI Check connection collected three real Claude windows with successful source timestamp 2026-10-17T13:12:07Z. Settings displayed Connected. The actual small desktop widget repainted with all three remaining allowances and matching local refresh time; reset times matched the official usage panel. The prior blank-widget failure is resolved for this tested account and machine.

Remaining acceptance: natural credential renewal, reboot/login-item lifecycle, network/revocation recovery on the separate Mac, browser-download quarantine, fresh macOS-user setup, medium/large actual desktop placement, tinted mode and Intel. No claim of permanent authentication or universal compatibility.

## Both providers on the separate Mac

October 17, 2026: the official Codex CLI 0.160.0 bundled with the installed ChatGPT desktop app already had a ChatGPT sign-in. Enabling ChatGPT in widget Settings and refreshing produced a successful source observation at 13:16:33Z, alongside a renewed Claude observation at 13:16:32Z. The actual small desktop widget displayed both providers. This corrects the earlier limited standard-path search that missed the bundled tool. No additional installation, credential transfer or new sign-in was needed.

Both Macs returned the same weekly-only Codex allowance. The missing five-hour window is omitted, not replaced with zero or synthetic data. Targeted tests against the native reader and Python reference confirmed both five-hour-plus-weekly and weekly-only responses across pro, plus and unknown plan labels. Display selection uses returned windows, not a hard-coded plan-name restriction. These synthetic checks do not establish which subscriptions the provider currently assigns five-hour limits to.
