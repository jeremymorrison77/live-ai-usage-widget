# Validation record

## 1.3.0 (build 32) — 10/19/2026

All three widget sizes placed on a fresh test Mac's desktop and checked live in every combination: Bars and Solar, Show amount used off and on, both accounts, Claude Code only, ChatGPT Codex only, plus the small widget with two readings chosen. Numbers and fills switch between left and used, rings fill clockwise, both styles share one background, rows spread evenly and stay at the top when few. Release ZIP as a real download: moved itself and connected both accounts by itself. A 1.2.0 install recorded "1.3.0 available" for the widget's status line, updated in about 1 second, and the notice cleared. Published files downloaded back and checksums matched. Notarization Accepted (submission 4a277ce8-49b6-43fc-aac0-19ccd9c2636c; app ZIP SHA-256 548c2764bfd5fe18dabebc874dfc53e210026badd1c52e075a9524ab747e3f8e).

## 1.2.0 (build 31) — 10/19/2026

Release ZIP as a real download on a fresh macOS 15.7.7 test Mac with both tools signed in: moved itself, connected both by itself, US dates on by default, no update notice (latest was 1.1.9). In-app update from 1.1.9: about 1 second, both still connected, no notice left behind. Widget "Version X available" status line checked only in a drawn sample (all sizes, both styles); it first shows for real when a newer version than 1.2.0 is published. Published files downloaded back and checksums matched. Notarization Accepted (submission b7193822-12f1-4b56-b35a-409e4d89321b; app ZIP SHA-256 98c4bdecfc49ba0334dee94e3770f04a8eb074bad4780f1633b0ff0daa06f7bf).

## 1.1.9 (build 30) — 10/18/2026

Release ZIP, marked as downloaded and opened from Downloads on a fresh macOS 15.7.7 virtual Mac with both tools signed in: Gatekeeper, Move to Applications, then both accounts connected by themselves in 12 seconds. In-app update from 1.1.8 on another fresh test Mac: updated in about 1 second, both accounts still connected. Published files downloaded back and checksums matched. Notarization Accepted (submission 99935e08-6610-42f7-8f88-88ff59cfdb62; app ZIP SHA-256 1ad73907c795f79a742167dd3cc3c3936353ceb8999fd1b34a61fccf809676bb).

## 1.1.8 (build 29) — 10/18/2026

Release ZIP installed on a fresh macOS 15.7.7 virtual Mac with Claude Code 2.1.302 signed in but never opened (the tester's state): Connect → folder trust ok → readings in about 12 seconds. Same state with 1.1.7 reproduced the tester's stall. Notarization Accepted (submission 65086bdb-0929-49d0-9e38-0c017eb53784; app ZIP SHA-256 ddb7277a5e0288482bcf8b3f4bf314dc4629924f8e3a5fd4f07f3f39aecfcbaa).

New-user matrix, 10/18/2026, published 1.1.8 ZIP (checksum matched), marked as downloaded and opened from Downloads on fresh macOS 15.7.7 virtual Macs:
- Neither tool: Gatekeeper prompt, Move to Applications offer, both accounts show Install. Install worked for Claude Code (13 s) and ChatGPT Codex (5 s). Connect without sign-in opens claude.ai sign-in in Safari (not completed).
- Claude Code alone (signed in, never opened): Connect → folder trust → three readings in 13 s.
- ChatGPT Codex alone: first launch connected it by itself in 1 s; Claude Code shows Install.
- Both: first launch connected both by itself in 9 s. ChatGPT sign-in through the app's own browser sign-in worked (device-code sign-in is off on the owner's account).
- Login item points to /Applications after the move and reopened the app after a restart.
- Bug: opened from Downloads and moved, first-launch auto-connect is skipped. The hidden first copy marks it done, then quits for the move before it finishes; the moved copy then shows Connect.
- Fixed in 1.1.9 (signed test build): quit during first-launch detection, then opened from Applications, connected both accounts by itself; Move to Applications with both signed in also connected. Opened from Downloads without the download mark, the move asks macOS permission for the Downloads folder first; the app waits on that question.
- Minor: while ChatGPT sign-in was still open, a check reported ChatGPT as rate limited rather than not signed in.

## 1.1.7 (build 28) — 10/18/2026

First-run Claude Code handling tested with a scripted fake that shows the three welcome screens; the real fresh-install case awaits the tester's update. Notarization Accepted (submission 24ee8af2-33f8-47ba-9198-e5f629dbea5b; app ZIP SHA-256 3e076324cdcc81e7c1016f17cbc6868e8ea2b5502e2fd4b366e38f753543d663).

## 1.1.6 (build 27) — 10/18/2026

Owner confirmed refresh works after the stale widget helper was stopped; launch showed no Settings window on screen. Notarization Accepted (submission 41b0b099-fc8c-4739-b852-d349c158a504; app ZIP SHA-256 ef0a13c1dd3eac1729e8d36785c2e587616a079ae13a5dc9495ace96d87d4278). The reopen-after-update path is first exercised by the next update.

## 1.1.5 (build 26) — 10/18/2026

Terminal lookup fallback (tested: finds /bin/ls through the login shell) and install guard. Notarization Accepted (submission 21baea47-ce46-4d51-81ae-3a801fccd65e; app ZIP SHA-256 9a999e47baf4bbf1b6a0cc3c894a9a61abeb8d7c2ce3844575444c1d33dbd89d).

## 1.1.4 (build 25) — 10/18/2026

Refresh behavior verified by filming the owner's desktop widget (with permission): Checking within about a second, old bars fade, new bars grow from the left; widget refresh link no longer opens Settings; rate-limit countdown shown. Notarization Accepted (submission c54e84f6-b999-4247-97ba-fd5a23248d46; app ZIP SHA-256 c2761228fba9a199f26fbbf7398c2c9444e35c5bb91b5e150d3ee67ef37d5932).

## 1.1.3 (build 24) — 10/18/2026

Settings opens at the top with no cursor in any box (checked in a drawn window at the default 520 × 640 size). Notarization Accepted (submission 5d3ae6bc-aba9-4c82-a323-f93a1546d17f; app ZIP SHA-256 c495ac7733efaa0f809d4dd41ec6f64b96842e812866b2ff82174562e91ebedb).

## 1.1.2 (build 23) — 10/18/2026

Troubleshooting report and 3-day activity log. Tests cover cleaning of personal details and the 3-day trim; the installed build wrote the expected launch, check and update lines on the development Mac. Notarization Accepted (submission 4edc3bd6-395d-4a6b-b96e-0112f1e21bf0; app ZIP SHA-256 8c0e92508d036b0337085acc4703fe4793d27714a1baa49b11057e63934d8191).

## 1.1.1 (build 22) — 10/18/2026

Claude Code sign-in fix, update check and install, Move to Applications. Tests pass, including a fake sign-in that prints the paste-code line. Update download, checksum and notarization/team checks verified against the real 1.1.0 ZIP served locally; a tampered checksum was refused. Notarization Accepted (submission 21d2cbe7-d7ff-43b7-a7c3-ee02d7cfe3a9; app ZIP SHA-256 cd606e48a6eb8dd51b0bdc2cbd6d03f03b61504653750a7efaa0d6b586eecc50). The full one-click swap is first exercised when a later release ships; real Claude sign-in through the fixed flow not yet repeated.

## 1.1.0 (build 21) — 10/18/2026

Account rows, naming, loading rows and plan-limit labels from owner testing on the development Mac. Tests, signed build and notarization pass (submission beb517a7-cad3-405a-8188-9ce5cfd09bab Accepted; app ZIP SHA-256 66441efd421eeb5e7c2e36277f241245016331a2e703d144ad47cfcb17061f7a). Owner tested each change in the installed app. Clean-machine install and long-term sign-in renewal are still unverified.

## 1.0.1 (build 14) — 10/17/2026

Terminal-free connect flow. Tests, signed build and notarization pass (submission 8da8a2bc-259e-4e85-8d49-c1059463c571 Accepted; app ZIP SHA-256 05d8853e4fc1a605d9c6931434a731af71d48b350873a2460287f5b0594a1d36). On the development Mac the owner completed ChatGPT browser sign-in through the new flow. Long-term sign-in renewal is still unverified.

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
