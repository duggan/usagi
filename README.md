# usagi

A minimalist Claude usage tracker for the macOS menu bar.

usagi shows your Claude.ai session usage as a small gauge in the menu bar, and the full picture — the rolling 5‑hour session, the weekly limit, and any paid overage spend — in a native dropdown.

> "Beware of bugs in the above code; I have only specified it, not written it." – @duggan

## Install

```
brew tap duggan/usagi
brew install --cask usagi
```

Or grab the DMG from [Releases](https://github.com/duggan/usagi/releases/latest) and drag to Applications.

Sign in with your Claude account on first launch — the session token lives in your macOS Keychain and never leaves the machine.

## Privacy & how it works

- **It only ever talks to `claude.ai`** — an embedded `WKWebView` pointed at `claude.ai/login` to sign in, then `claude.ai/api/...` to read your usage windows and overage limit. Nothing is sent anywhere else.
- **No telemetry, no analytics, no crash reporting** — usagi doesn't phone home, full stop.
- **Your session token stays in the macOS Keychain** (service `ie.duggan.usagi.session`). "Sign out" deletes that entry and clears the embedded web view's cookies/storage.
- **It uses an *unofficial* claude.ai API** — the same endpoints the website itself calls. They can change or break without notice; that's the main reason there'd ever be an update.
- "Launch at login" is the standard `SMAppService` mechanism — toggle it here, or in System Settings → General → Login Items.

## Debugging

When usagi misbehaves — blank bars, wrong account, "Signed out" loops — the menu-bar UI is too small to explain what happened, but every interesting decision is logged. Everything is prefixed `usagi:` so it filters cleanly.

**In Console.app**: open Console, pick your Mac in the sidebar, type `usagi:` in the search box, and click *Start streaming*. Then trigger a refresh (click the menu bar icon, or wait for the next interval).

Or stream from the terminal:

```
log stream --predicate 'eventMessage CONTAINS "usagi:"' --style compact
```

What to look for:

- `usagi: orgs count=N, selected=… (uuid)` — confirms which organisation was picked. If you're on a team/enterprise plan that ranks ahead of your personal org in the list, usage for the wrong org will be empty.
- `usagi: five_hour util=… resets_at=…` — the parsed 5‑hour window, logged on every successful refresh.
- `usagi: non-JSON response for /usage content-type=text/html …` — claude.ai handed back HTML instead of JSON (usually a Cloudflare challenge). The first ~200 bytes of the body are logged so you can confirm.
- `usagi: decode failed for /usage response: …` — the JSON parsed but didn't match the expected shape; the body preview is logged.

A nil/missing `five_hour` is treated as a hard failure rather than a silent zero, so a broken response surfaces as a visible error in the dropdown and a decode-failed log line — not blank bars.

## Build from source

Requires macOS 14+ to run, and Xcode 16 or newer to build — the SwiftUI code needs the macOS 15 SDK (`View.body` is `@MainActor` there). `swift test` runs the unit tests.

```
./build.sh                         # release build → bin/Usagi.app
UNIVERSAL=1 DMG=1 ./build.sh       # universal binary + DMG (drag-install)
open bin/Usagi.app
```

For a Developer ID-signed and notarized build:

```
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARIZE_PROFILE="usagi-notarize" \
DMG=1 UNIVERSAL=1 \
./build.sh
```

`NOTARIZE_PROFILE` is a `notarytool store-credentials` profile in your login keychain. Alternatively, pass `NOTARIZE_KEY` (path to `.p8`), `NOTARIZE_KEY_ID`, and `NOTARIZE_ISSUER` to use an App Store Connect API key directly.

## Releasing

Tag a commit `vX.Y.Z` and push. The `release` GitHub Actions workflow signs, notarizes, and publishes a DMG to the matching GitHub Release. The workflow runs inside a `release` environment with required-reviewer approval, so a stray tag cannot expose signing secrets.

### One-time release setup

1. **Export the Developer ID Application certificate** from Keychain Access (right-click → Export → `.p12` with a strong password). Then:
   ```
   base64 -i developer-id.p12 | pbcopy   # paste into MACOS_CERTIFICATE
   ```
2. **Create an App Store Connect API key** at [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api). Role: **Developer**. Apple lets you download the `.p8` exactly once. Then:
   ```
   base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy   # paste into APPLE_API_KEY
   ```
3. **Create a `release` environment** in repo Settings → Environments → New environment. Add yourself as a required reviewer.
4. **Add secrets to the `release` environment** (not repo-level secrets):

   | Secret | Value |
   | --- | --- |
   | `MACOS_CERTIFICATE` | base64 of the exported `.p12` |
   | `MACOS_CERTIFICATE_PWD` | the `.p12` password |
   | `KEYCHAIN_PWD` | any random password — used for the temp keychain |
   | `SIGN_IDENTITY` | full cert common name, e.g. `Developer ID Application: Ross Duggan (XXXXXXXXXX)` |
   | `APPLE_API_KEY` | base64 of the `.p8` |
   | `APPLE_API_KEY_ID` | 10-character Key ID from App Store Connect |
   | `APPLE_API_ISSUER_ID` | the Issuer ID UUID at the top of the Keys page |
   | `HOMEBREW_TAP_TOKEN` | *optional* — fine-grained PAT with **Contents: read & write** on `duggan/homebrew-usagi`; enables auto-bumping the cask. Omit it and the release just skips that step. |

The temporary keychain is deleted on every job exit (success or failure), so secrets never persist on the runner.

### Homebrew tap

The cask lives in [`duggan/homebrew-usagi`](https://github.com/duggan/homebrew-usagi) (`Casks/usagi.rb`). Its source of truth is [`homebrew/usagi.rb`](homebrew/usagi.rb) in this repo — the release workflow substitutes the new `version` + `sha256` and pushes the result to the tap, so a release auto-publishes the cask. Edit `homebrew/usagi.rb` here for anything else (zap paths, deps, …).

## Architecture

- **App.swift** — `AppDelegate` owning the `NSStatusItem` and its `NSMenu` (the first item hosts the SwiftUI usage bars; the rest are standard menu items rebuilt per state). The status-item image is redrawn reactively via `withObservationTracking` whenever `AppState` changes.
- **ViewModels/AppState.swift** — `@Observable` root state: phase, snapshot, overage, organization, refresh interval. Coordinates load → refresh → sign-out lifecycle.
- **Services/ClaudeAPIClient.swift** — `URLSession`-backed actor calling `claude.ai/api/organizations`, `/usage`, `/overage_spend_limit`. Sends `Cookie: sessionKey=...`.
- **Services/AuthCoordinator.swift** — `WKWebView` window pointed at `claude.ai/login`; observes the cookie store and persists the captured `sessionKey` to the Keychain.
- **Services/SessionStore.swift** — Keychain CRUD for the session key (service `ie.duggan.usagi.session`).
- **Services/UsageRefresher.swift** — Timer that drives `AppState.refresh()` on the configured interval.

## License

MIT.
