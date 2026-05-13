# Security

usagi runs entirely on your Mac. The only network destination is `claude.ai`, and the only secret it handles is the session cookie you sign in with.

## What usagi stores

- **Session token**: in the macOS Keychain (service `ie.duggan.usagi.session`), never logged, never sent anywhere except as the `Cookie` header on requests to `claude.ai/api/...`.
- **Preferences**: refresh interval and "launch at login" toggle, in `~/Library/Preferences/ie.duggan.usagi.plist`. No secrets.

usagi has no telemetry, no analytics, no crash reporting, and no remote logging. "Sign out" deletes the Keychain entry and clears the embedded WKWebView's cookies and storage.

## Unofficial API

usagi reads from claude.ai's internal API — the same endpoints the website itself calls. They can change or break without notice. That is the main reason there would ever be an update.

## Supported versions

Only the latest released version is supported.

## Reporting a vulnerability

Please email **ross@duggan.ie** with details. I'll respond as soon as I can. For non-sensitive bugs, prefer a GitHub issue.
