# Grok Bot support: overnight note (11/1/2026)

Historical note from November 1. Superseded by the November 2 [release preparation record](RELEASE-1.3.2.md); the original observations below are retained.

At the time, local only (nothing pushed, tagged, notarized or released):

- Branch `grokbot-usage`: reviewed. One fix (d5c28b5): Grok Bot's file is read on every one-minute check, so its attempt time changed every minute and the app redrew the widget every minute, spending macOS's widget reload budget. It now redraws only on a new reading or a changed outcome. Version bumped to 1.3.2 (build 34) in ef1c8c6. At your request, all "shared with other apps" text is gone from the widget and Settings (the file field is still read, just not shown).
- `bash scripts/test.sh` passes. Signed build with "Developer ID Application: JEREMY ALEXANDER MORRISON (7F78Q6T29S)", no keychain prompt. Not notarized (fine for this Mac; needed before sharing).
- Installed in /Applications and reopened. Grok Bot connected in Settings > Accounts (Connected). The widget extension (build 34) has read the Grok Bot reading (timeline-read.json).
- Backups: ~/Developer/live-ai-usage-widget-backups/installed-1.3.1-backup.app (the app that was in /Applications) and 1.3.1-signed-backup.app (also still at build/1.3.1-signed-backup.app).

Still to do with you:

- Look at the desktop widget yourself. No live screenshot was possible: Grok Bot isn't allowed to record the screen. The pictures in build/grokbot-preview/ are drawn from the real file, not the live widget.
- A Finder automation request may have appeared around 9:35 PM. It was cancelled; if a "wants to control Finder" box is still open, choose Don't Allow.
- To ship 1.3.2: CHANGELOG entry, notarize (`scripts/release.py`), package, push, release. To undo: quit the app and copy the backup app back into /Applications.
