# Changelog

## Unreleased

Clicking the widget's refresh button dims the readings at once and shows Checking… for at least two seconds. When Claude Code asks the app to wait (rate limited) and the last reading is still fresh, the widget and Settings no longer report a failure. The Trends style is gone; there are two styles, Clean and Solar (anyone on Trends moves to Clean). Settings apply as you change them; the Save settings button is gone. The widget no longer shows "Failed to load" when its numbers are only old: the app now redraws the widget only when readings change (macOS was ignoring once-a-minute redraws), and old readings show their time with a warning sign. The widget's refresh button checks usage without opening Settings. The menu item is now "Check usage now" and always runs, even if a regular check is under way.

## 1.1.3

The settings window opens at the top with no cursor in any box; the number boxes take the cursor only when clicked.

## 1.1.2

Troubleshooting in Settings: Save report… writes a plain-text report (versions, where the app runs from, tools found and signed in, last checks, and the past three days of activity) to send to the developer. The activity log stays on the Mac in ~/Library/Logs/Live AI Usage Widget, keeps three days and never grows past 256 KB, and leaves out account names, emails, passwords, sign-in codes and links.

## 1.1.1

Fixed Claude Code browser sign-in (Authorize led to a "can't be reached" page). The app checks for updates and installs them in one click after checking they are Apple-approved and from the same developer. Opened from Downloads, it offers to move itself into Applications. Finds Claude Code installed with npm, nvm, Bun or Volta. Setup help names the widget up front.

## 1.1.0

Each account is one line: Claude Code or ChatGPT Codex and a single button that says what it will do (Install, Connect, Connecting…, Connected, or Sign in, Update, Finish setup, Try again, Open sign-in page). The spinner shows inside the button of the account that is working. Disconnecting one account no longer drops the other. Accounts are named Claude Code and ChatGPT Codex everywhere. The menu bar shows one line per account. First launch connects tools that are already signed in, and Open at login is on by default. The settings window can be resized and remembers its size, opens with nothing selected, and no longer shifts while checking in the background. A number typed into a field is kept when Save settings is clicked. A newly connected account appears on the widget right away with Loading… rows until its first reading arrives. The Get started section is now called Setup help, matching its button. Small widget readings lists limits your plan does not have (for example the 5-hour limit on ChatGPT Pro, or the weekly Fable limit outside Claude Max and Premium seats) grayed out as "Not included in your plan".

## 1.0.1

Connecting no longer needs Terminal. The Connect window shows three steps and can be closed with Cancel or Escape. Install shows a green check when Claude Code or Codex is already on the Mac; otherwise it installs the official tool in the background. Sign in opens the browser for both Claude and ChatGPT and checks the connection when done. Check connection answers Claude Code's one-time folder-trust question for the app's own empty folder. Removed the extra note under Check every.

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
