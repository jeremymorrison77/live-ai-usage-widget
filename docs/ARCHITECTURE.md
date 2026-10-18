# Architecture and recovery

The native companion owns collection. Its timer checks once per minute while running; the native Swift collector gates each provider independently to five minutes after success and fifteen minutes after failure. It uses a nonblocking file lock and atomic state replacement. A clock rollback cannot postpone retries indefinitely. The app requests WidgetKit reload after publication; timeline entries also age existing values without requiring a new reading.

Claude Code is read through its own `/usage` terminal panel in a bounded disposable working directory. It disables tools and hooks for the probe. The parser requires valid percentages and explicit reset timezones and accepts optional per-model weekly limits. Terminal output must settle before accepting it. UI changes, new CLI prompts or unsupported date formats can break parsing; failure is preferable to guessed data.

ChatGPT Codex uses the official tool's stdio app-server interface: initialize, initialized, account/rateLimits/read. It never starts a conversation or turn. It selects the Codex bucket and rejects malformed limits. Both readers cap output and time out; they terminate only their own spawned helper process groups, never programs selected by name.

Provider authentication renewal belongs to the provider's official CLI. This app does not copy, refresh or manipulate tokens. It retries after errors; revoked sessions, MFA, policy changes and expired authorization may still require the user to sign in. Do not promise permanent authentication or consider cached data proof of renewal.

The shared Swift store validates incoming numbers and timestamps, keeps newer observations and refresh outcomes, uses file locking and atomic writes, and caps history per metric. Switching providers in Settings generates a cache generation; results from an earlier generation cannot publish into the new selection. It clears graph history to avoid linking different accounts. Changing accounts externally without this workflow remains an acceptance limitation.

Trends show average percentage points consumed per minute between genuine observations. At least two readings with the same reset identity are needed. Resets, corrections, long gaps and missing reset identity never create measured activity. Missing coverage is drawn flat; vertical connectors at its boundaries are coverage transitions, not observed spikes. Scales are per row. A daily or weekly allowance percentage is not a token count or dollar estimate.

No private assistant integration, recording service, conversation-history fallback, external skill, personal workspace, developer identity or existing account state is required. The app group is supplied at build time. Development packaging does not install, activate or change an existing application.

Provider interfaces: [Claude CLI](https://code.claude.com/docs/en/cli-reference) and [Codex app server](https://developers.openai.com/codex/app-server/). Distribution uses [Apple Developer ID](https://developer.apple.com/developer-id/) and notarization. The Python adapters remain development/reference fixtures only; they are not included in the app bundle.
