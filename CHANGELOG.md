# Changelog

## 1.0.1

The Connect window is clearer and can be closed (Cancel or Escape). It notices when Claude Code or Codex is already installed and skips that step; otherwise it offers Install for me (Claude, runs the official installer in Terminal) or a link. Sign in and Finish setup open Terminal and run the command for you. Removed the extra note under Check every.

## 1.0.0

First full release. Includes everything below from 0.3.1 (never released separately):


Get started hides itself once all three steps are done; a Setup help button beside Save settings brings it back. Both buttons are centered at the bottom. The Preview usage section is gone. The widget gallery now shows sample readings instead of "Waiting for readings", and its description is simply "Claude and ChatGPT usage remaining." The Show me how guide names the widget exactly and explains up front why this step is manual. New Updates setting: check every N minutes (default 5, any value from 1 to 1,440); failed checks still wait at least 15 minutes. The window opens scrolled to the top, and status messages are plain (no message when there is nothing to report). The app now lives in the menu bar (Settings, Check now, Quit) instead of the Dock; once fully set up it starts quietly there, for example at login.

## 0.3.0 — beta (prerelease)

Renamed to Live AI Usage Widget (new bundle identifier and app group, so earlier settings do not carry over). The app now opens straight to one setup window with three Get started steps: connect accounts, add the widget to the desktop (with a Show me how guide and a check that turns green once a widget is placed) and Open at login. The separate preview window is gone. Clean is the default style. The widget's gear and refresh buttons work with the window closed.

## 0.2.1 — beta candidate

Fix first-run Claude collection: report outdated CLI versions clearly, offer official setup and immediate connection retry, disable Chrome integration and optional settings for the reader, and cancel only the optional auto-mode migration question. Trust/login prompts still require the user. Separate-Mac Claude sign-in, real usage and desktop repaint now pass; natural renewal remains unverified.

## 0.2.0 — beta candidate

Native Swift collection removes the runtime Python requirement. Adds Clean bars, Solar rings, per-metric small-widget selection, official Terminal sign-in, centered linked color thresholds, account checkboxes, a custom app icon and working settings deep links. Signed app packaging supports Apple notarization, stapling and SHA-256 verification. MIT license. Independent-Mac installation, actual desktop widget rendering, reboot and natural token renewal remain acceptance items.

## 0.1.0 — developer preview

Standalone companion/widget source, bounded Claude/Codex readers, provider selection, recovery state, actual-data Trends, configurable colors and date format.
