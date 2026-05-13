import XCTest
@testable import Usagi

/// Tests the pure cookie-filter helpers extracted from `AuthCoordinator`.
/// The WKWebView side of `AuthCoordinator` is deliberately not exercised here.
final class AuthCoordinatorTests: XCTestCase {

	// MARK: - isSessionCookie

	func testIsSessionCookieAcceptsClaudeDomain() {
		XCTAssertTrue(AuthCoordinator.isSessionCookie(makeCookie(name: "sessionKey",
		                                                        value: "sk-ant-abc",
		                                                        domain: "claude.ai")))
	}

	func testIsSessionCookieAcceptsClaudeSubdomain() {
		XCTAssertTrue(AuthCoordinator.isSessionCookie(makeCookie(name: "sessionKey",
		                                                        value: "sk-ant-abc",
		                                                        domain: ".claude.ai")))
	}

	func testIsSessionCookieRejectsOtherName() {
		XCTAssertFalse(AuthCoordinator.isSessionCookie(makeCookie(name: "csrfToken",
		                                                         value: "sk-ant-abc",
		                                                         domain: "claude.ai")))
	}

	func testIsSessionCookieRejectsOtherDomain() {
		XCTAssertFalse(AuthCoordinator.isSessionCookie(makeCookie(name: "sessionKey",
		                                                         value: "sk-ant-abc",
		                                                         domain: "example.com")))
	}

	// MARK: - extractSessionKey

	func testExtractFindsMatchingCookie() {
		let cookies = [
			makeCookie(name: "intercom", value: "junk", domain: "claude.ai"),
			makeCookie(name: "sessionKey", value: "sk-ant-real", domain: "claude.ai"),
		]
		XCTAssertEqual(AuthCoordinator.extractSessionKey(from: cookies), "sk-ant-real")
	}

	func testExtractRequiresSkAntPrefix() {
		let cookies = [makeCookie(name: "sessionKey", value: "not-a-token", domain: "claude.ai")]
		XCTAssertNil(AuthCoordinator.extractSessionKey(from: cookies))
	}

	func testExtractReturnsNilForEmpty() {
		XCTAssertNil(AuthCoordinator.extractSessionKey(from: []))
	}

	func testExtractReturnsNilWhenNoMatch() {
		let cookies = [makeCookie(name: "other", value: "sk-ant-abc", domain: "claude.ai")]
		XCTAssertNil(AuthCoordinator.extractSessionKey(from: cookies))
	}

	// MARK: - Helpers

	private func makeCookie(name: String, value: String, domain: String) -> HTTPCookie {
		HTTPCookie(properties: [
			.name: name,
			.value: value,
			.domain: domain,
			.path: "/",
		])!
	}
}
