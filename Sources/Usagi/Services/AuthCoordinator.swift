import AppKit
import WebKit

/// Opens an embedded WKWebView at claude.ai/login, watches its cookie store
/// for the `sessionKey` cookie, and persists it to the Keychain.
@MainActor
final class AuthCoordinator: NSObject {
	private var window: NSWindow?
	private var webView: WKWebView?
	private var observer: CookieObserver?
	private var onCapture: ((String) -> Void)?

	func presentLogin(onCapture: @escaping (String) -> Void) {
		self.onCapture = onCapture

		// Reuse the existing window if the user clicked Sign In twice.
		if let window {
			window.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
			return
		}

		let config = WKWebViewConfiguration()
		// Persistent data store so the user isn't logged out across app restarts
		// during onboarding hiccups; we wipe it on signOut().
		config.websiteDataStore = .default()

		let webView = WKWebView(frame: .zero, configuration: config)
		webView.navigationDelegate = self
		webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
		self.webView = webView

		let observer = CookieObserver { [weak self] cookies in
			Task { @MainActor in
				self?.handleCookies(cookies)
			}
		}
		config.websiteDataStore.httpCookieStore.add(observer)
		// Prime: read existing cookies in case the user is already logged in.
		config.websiteDataStore.httpCookieStore.getAllCookies { cookies in
			Task { @MainActor in
				self.handleCookies(cookies)
			}
		}
		self.observer = observer

		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
			styleMask: [.titled, .closable, .resizable, .miniaturizable],
			backing: .buffered,
			defer: false
		)
		window.title = "Sign in to Claude"
		window.contentView = webView
		window.center()
		window.isReleasedWhenClosed = false
		window.delegate = self
		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		self.window = window

		webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
	}

	private func handleCookies(_ cookies: [HTTPCookie]) {
		guard let cookie = cookies.first(where: { isSessionCookie($0) }),
		      cookie.value.hasPrefix("sk-ant-")
		else { return }

		do {
			try SessionStore.write(cookie.value)
			onCapture?(cookie.value)
			close()
		} catch {
			NSLog("usagi: failed to persist session key: \(error)")
		}
	}

	private func isSessionCookie(_ cookie: HTTPCookie) -> Bool {
		cookie.name == "sessionKey" && (cookie.domain.hasSuffix("claude.ai") || cookie.domain == "claude.ai")
	}

	/// Releases everything tied to the login session. Safe to call multiple times.
	/// Does NOT itself close the window — call `close()` for that.
	private func teardown() {
		if let observer, let store = webView?.configuration.websiteDataStore.httpCookieStore {
			store.remove(observer)
		}
		observer = nil
		onCapture = nil
		webView = nil
		window?.delegate = nil
		window = nil
	}

	private func close() {
		// Snapshot the window so we can dismiss it after teardown nils it out.
		// Detaching the delegate inside teardown() prevents windowWillClose from
		// re-entering close() and overflowing the stack.
		let w = window
		teardown()
		w?.close()
	}

	/// Wipes the WKWebView's persistent cookies/storage. Call on sign-out.
	static func clearWebData() async {
		let store = WKWebsiteDataStore.default()
		let types = WKWebsiteDataStore.allWebsiteDataTypes()
		let records = await store.dataRecords(ofTypes: types)
		await store.removeData(ofTypes: types, for: records)
	}
}

extension AuthCoordinator: WKNavigationDelegate {
	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		// After each navigation, force a cookie poll — some flows fire cookies
		// before the WKHTTPCookieStoreObserver gets called.
		webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
			Task { @MainActor in self.handleCookies(cookies) }
		}
	}
}

extension AuthCoordinator: NSWindowDelegate {
	func windowWillClose(_ notification: Notification) {
		// User dismissed the login window manually. Tear down state without
		// calling close() — the window is already closing.
		teardown()
	}
}

private final class CookieObserver: NSObject, WKHTTPCookieStoreObserver {
	let onChange: ([HTTPCookie]) -> Void

	init(onChange: @escaping ([HTTPCookie]) -> Void) {
		self.onChange = onChange
	}

	func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
		cookieStore.getAllCookies { [onChange] cookies in
			onChange(cookies)
		}
	}
}
