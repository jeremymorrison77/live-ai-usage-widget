# Grok Bot usage file

Grok Bot has no usage tool or public usage interface. A Grok Bot routine writes its usage to one small file on this Mac, and the app reads that file during its normal check. This page is where the routine looks up where and what to write.

## Where to write

```
~/Library/Application Support/Live AI Usage Widget/grokbot-usage.json
```

`~` is the signed-in person's home folder (`/Users/NAME`). The folder name has spaces; quote the path.

Only the app reads this file, and the app is not sandboxed, so it can read it in place. The widget is sandboxed and never reads it: the app copies the reading into the widget's shared app-group container (`status.json`) along with the Claude Code and ChatGPT Codex readings. Don't write into the app-group container yourself.

## What to write

```json
{"source":"grokbot","plan":"Ultra","weekly":{"usedPercent":7.2,"resetsAt":"2026-11-08T16:23:00Z","sharedWithOtherApps":true},"updatedAt":"2026-11-01T21:20:00Z"}
```

- `source`: must be `"grokbot"`.
- `weekly.usedPercent`: a number from 0 to 100. The app shows it as used or left (100 minus it), following Show amount used in Settings.
- `weekly.resetsAt`: when the weekly limit resets, an ISO 8601 time with a time zone (`Z` or an offset). Optional; without it no reset time is shown.
- `weekly.sharedWithOtherApps`: whether the limit is shared with other apps on the plan. Optional; read and kept but not shown anywhere.
- `updatedAt`: when the reading was taken, ISO 8601 with a time zone. Required.
- `plan`: kept for reference; not shown.
- `creditsUSD`: optional top-level number, USD remaining in additional usage credits, never negative. Accepted range: 0 through 1,000,000,000; missing, invalid or out-of-range values are ignored without losing the weekly reading. Example: `"creditsUSD":300.0`.

Keep the file under 16 KB. Write it in one step (write a temporary file in the same folder, then rename it over this one) so the app never reads half a file.

## How the app uses it

- Read on each of the app's regular checks (its existing once-a-minute timer). Nothing new runs for it: no timer, file watcher, background process, network call or launch agent.
- Settings > Accounts shows Grok Bot as Connected while the file is there and `updatedAt` is under 3 hours old. Otherwise it says "No usage file yet", "Reading is over 3 hours old" or "Couldn't read usage file", with a Try Again button. Disconnect only hides Grok Bot.
- A reading older than 3 hours fades and reads "Old reading" on the widget, like other old readings. Writing hourly leaves room for two missed writes.
- A file that is missing or unreadable keeps the last good reading, which then ages as usual.

The one-minute file check does not itself redraw the widget. A new reading or changed outcome triggers the redraw; unchanged attempt times do not spend the widget reload budget.

At 100% weekly usage, the weekly row follows Show amount used: **100% used** or **0% left**. Below 100%, credits are hidden. The menu shows the same amounts.

## Live credits file

The app also reads this independent file on the same once-a-minute check:

```
~/Library/Application Support/Live AI Usage Widget/grokbot-credits.json
```

```json
{"source":"grokbot-credits","creditsAvailableUSD":295.64,"usedThisMonthUSD":304.37,"monthlyLimitUSD":null,"weeklyUsedPercent":100,"weeklyResetsAt":"2026-11-08T16:23:00Z","burn24hUSD":null,"updatedAt":"2026-11-05T05:52:00Z"}
```

- `source` must be `grokbot-credits`; `creditsAvailableUSD` is a finite, nonnegative number.
- `usedThisMonthUSD`, `monthlyLimitUSD`, and `burn24hUSD` are nonnegative numbers or null (omitted values are also accepted).
- `weeklyUsedPercent` is a number from 0 to 100. `weeklyResetsAt` and required `updatedAt` are ISO UTC timestamps ending in `Z`. Future observations beyond 30 seconds are rejected.
- Keep the file under 16 KB. The app only reads it and copies the validated reading into app-group `status.json`; the widget never reads either source file directly. Neither file is modified by the app.
- The newer file's `updatedAt` decides weekly usage and reset time. Ties keep the original weekly file. A newer credits file replaces the old `creditsUSD`; an older credits file supplies a balance only if the weekly file has none. Missing or invalid credits files never break a valid weekly file. A valid credits file can also supply weekly usage when the original file is unavailable.
- Once weekly usage is exhausted, **Grok credits** shows dollars available to two decimals, with **· $X.XX/day** when `burn24hUSD` is present.
- The bar or ring always depletes with available credits. Its fill is available / monthly limit when a positive limit exists; otherwise, with no limit, it is available / (available + used this month). Missing or zero denominators show only the amount. No starting balance is invented.
- At $100 or more the row uses the existing normal colour; below $100 it uses the middle colour, and below $25 the low/red colour. The colour preference remains respected.
- Credits have their own clock: more than eight hours after `updatedAt`, the row fades and shows **Old reading**, independently of weekly freshness. Original-file-only credits retain that file's three-hour freshness rule.

Preview evidence for 1.3.3 is kept in the ignored `build/grok-credits-1.3.3/` folder: below-limit, exhausted-295.64, under-100, under-25, and stale, each with `-used.png` and `-left.png` versions showing both styles and all three sizes.
