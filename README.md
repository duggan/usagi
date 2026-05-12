# usagi

A minimalist Claude usage tracker for the macOS menu bar.

usagi shows your weekly Claude.ai usage as a small bar in the menu bar (e.g. `▓▓▓▓░ 42%`) and surfaces the rest — Opus weekly, the rolling 5-hour session, and any paid overage spend — in a compact popover.

## Install

```
brew tap duggan/usagi
brew install --cask usagi
```

Or grab the DMG from [Releases](https://github.com/duggan/usagi/releases/latest) and drag to Applications.

Sign in with your Claude account on first launch — the session token lives in your macOS Keychain and never leaves the machine.

## Build from source

Requires macOS 14+ and Swift 5.9 (Xcode 15.4 or newer).

```
./build.sh                         # debug-quality release build
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

The temporary keychain is deleted on every job exit (success or failure), so secrets never persist on the runner.

### Updating the Homebrew tap

After a release, edit `homebrew-usagi/Casks/usagi.rb` (separate tap repo) with the new version and the SHA256 from the release notes, then push.

## Architecture

- **App.swift** — `AppDelegate` owning the `NSStatusItem` and `NSPopover`. The status item title is updated reactively via `withObservationTracking` whenever `AppState` changes.
- **ViewModels/AppState.swift** — `@Observable` root state: phase, snapshot, overage, organization, refresh interval. Coordinates load → refresh → sign-out lifecycle.
- **Services/ClaudeAPIClient.swift** — `URLSession`-backed actor calling `claude.ai/api/organizations`, `/usage`, `/overage_spend_limit`. Sends `Cookie: sessionKey=...`.
- **Services/AuthCoordinator.swift** — `WKWebView` window pointed at `claude.ai/login`; observes the cookie store and persists the captured `sessionKey` to the Keychain.
- **Services/SessionStore.swift** — Keychain CRUD for the session key (service `ie.duggan.usagi.session`).
- **Services/UsageRefresher.swift** — Timer that drives `AppState.refresh()` on the configured interval.

## License

MIT.
