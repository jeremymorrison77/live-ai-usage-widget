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

Keep the file under 16 KB. Write it in one step (write a temporary file in the same folder, then rename it over this one) so the app never reads half a file.

## How the app uses it

- Read on each of the app's regular checks (its existing once-a-minute timer). Nothing new runs for it: no timer, file watcher, background process, network call or launch agent.
- Settings > Accounts shows Grok Bot as Connected while the file is there and `updatedAt` is under 3 hours old. Otherwise it says "No usage file yet", "Reading is over 3 hours old" or "Couldn't read usage file", with a Try Again button. Disconnect only hides Grok Bot.
- A reading older than 3 hours fades and reads "Old reading" on the widget, like other old readings. Writing hourly leaves room for two missed writes.
- A file that is missing or unreadable keeps the last good reading, which then ages as usual.

The one-minute file check does not itself redraw the widget. A new reading or changed outcome triggers the redraw; unchanged attempt times do not spend the widget reload budget.
