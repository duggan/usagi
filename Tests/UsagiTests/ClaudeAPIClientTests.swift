import XCTest
@testable import Usagi

/// Exercises the API client's HTTP/decoding path via a URLProtocol stub.
/// These tests don't hit the network; they wire a custom `URLSession` whose
/// only protocol handler is `StubURLProtocol`, which returns whatever the
/// current `handler` closure produces.
final class ClaudeAPIClientTests: XCTestCase {

	private var session: URLSession!
	private var client: ClaudeAPIClient!

	override func setUp() {
		super.setUp()
		let config = URLSessionConfiguration.ephemeral
		config.protocolClasses = [StubURLProtocol.self]
		session = URLSession(configuration: config)
		client = ClaudeAPIClient(session: session)
		StubURLProtocol.handler = nil
		StubURLProtocol.lastRequest = nil
	}

	override func tearDown() {
		StubURLProtocol.handler = nil
		StubURLProtocol.lastRequest = nil
		session = nil
		client = nil
		super.tearDown()
	}

	// MARK: - Success path

	func testOrganizationsDecodesAndSendsSessionCookie() async throws {
		StubURLProtocol.handler = { request in
			(Self.response(200, for: request),
			 Data(#"[{"uuid":"org-1","name":"Acme"}]"#.utf8))
		}

		let orgs = try await client.organizations(sessionKey: "sk-ant-abc")
		XCTAssertEqual(orgs.first?.uuid, "org-1")
		XCTAssertEqual(orgs.first?.name, "Acme")
		XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Cookie"),
		               "sessionKey=sk-ant-abc")
		XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/api/organizations")
	}

	// MARK: - HTTP error mapping

	func testUnauthorizedOn401() async {
		StubURLProtocol.handler = { request in (Self.response(401, for: request), Data()) }
		await assertThrows(ClaudeAPIError.unauthorized) {
			_ = try await self.client.organizations(sessionKey: "sk-ant-abc")
		}
	}

	func testUnauthorizedOn403() async {
		StubURLProtocol.handler = { request in (Self.response(403, for: request), Data()) }
		await assertThrows(ClaudeAPIError.unauthorized) {
			_ = try await self.client.organizations(sessionKey: "sk-ant-abc")
		}
	}

	func testHttp500SurfacedAsHttp() async {
		StubURLProtocol.handler = { request in (Self.response(500, for: request), Data()) }
		do {
			_ = try await client.organizations(sessionKey: "sk-ant-abc")
			XCTFail("expected throw")
		} catch ClaudeAPIError.http(let code) {
			XCTAssertEqual(code, 500)
		} catch {
			XCTFail("unexpected error: \(error)")
		}
	}

	func testOverage404TreatedAsNil() async throws {
		StubURLProtocol.handler = { request in (Self.response(404, for: request), Data()) }
		let result = try await client.overage(sessionKey: "sk-ant-abc", organizationID: "org-1")
		XCTAssertNil(result)
	}

	func testUsage404SurfacedAsError() async {
		StubURLProtocol.handler = { request in (Self.response(404, for: request), Data()) }
		do {
			_ = try await client.usage(sessionKey: "sk-ant-abc", organizationID: "org-1")
			XCTFail("expected throw")
		} catch ClaudeAPIError.http(let code) {
			XCTAssertEqual(code, 404)
		} catch {
			XCTFail("unexpected error: \(error)")
		}
	}

	// MARK: - Transport / decoding

	func testTransportErrorWrapped() async {
		StubURLProtocol.handler = { _ in
			throw NSError(domain: "TestTransport", code: 42)
		}
		do {
			_ = try await client.organizations(sessionKey: "sk-ant-abc")
			XCTFail("expected throw")
		} catch ClaudeAPIError.transport {
			// ok
		} catch {
			XCTFail("unexpected error: \(error)")
		}
	}

	func testDecodeFailureReportsPath() async {
		StubURLProtocol.handler = { request in
			(Self.response(200, for: request),
			 Data(#"[{"uuid":"org-1"}]"#.utf8))   // missing "name"
		}
		do {
			_ = try await client.organizations(sessionKey: "sk-ant-abc")
			XCTFail("expected throw")
		} catch ClaudeAPIError.decoding(let path, _) {
			XCTAssertFalse(path.isEmpty)
			XCTAssertTrue(path.contains("name"), "expected path to reference missing key, got \(path)")
		} catch {
			XCTFail("unexpected error: \(error)")
		}
	}

	func testEmptySessionKeyRejected() async {
		await assertThrows(ClaudeAPIError.noSessionKey) {
			_ = try await self.client.organizations(sessionKey: "")
		}
	}

	// MARK: - Cloudflare / non-JSON

	/// A Cloudflare challenge that returns HTTP 200 + `text/html` must surface
	/// as a distinct `.notJSON` error rather than silently producing zero-filled
	/// usage. This was the underlying cause of "all bars are 0%" for the first
	/// external tester.
	func testNonJSONResponseSurfacesAsNotJSON() async {
		StubURLProtocol.handler = { request in
			let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
				headerFields: ["Content-Type": "text/html; charset=utf-8"])!
			return (resp, Data("<html><body>Just a moment...</body></html>".utf8))
		}
		do {
			_ = try await client.organizations(sessionKey: "sk-ant-abc")
			XCTFail("expected throw")
		} catch ClaudeAPIError.notJSON(let ct, _) {
			XCTAssertTrue(ct.contains("html"), "expected html content-type, got \(ct)")
		} catch {
			XCTFail("unexpected error: \(error)")
		}
	}

	/// Verifies the browser-fingerprint headers actually reach the wire. If any
	/// of these go missing, Cloudflare starts handing back challenge pages.
	func testRequestSendsBrowserHeaders() async throws {
		StubURLProtocol.handler = { request in
			(Self.response(200, for: request), Data("[]".utf8))
		}
		_ = try await client.organizations(sessionKey: "sk-ant-abc")
		let req = StubURLProtocol.lastRequest
		XCTAssertEqual(req?.value(forHTTPHeaderField: "anthropic-client-platform"), "web_claude_ai")
		XCTAssertEqual(req?.value(forHTTPHeaderField: "origin"), "https://claude.ai")
		XCTAssertEqual(req?.value(forHTTPHeaderField: "referer"), "https://claude.ai/settings/usage")
		XCTAssertEqual(req?.value(forHTTPHeaderField: "sec-fetch-site"), "same-origin")
		XCTAssertTrue(req?.value(forHTTPHeaderField: "user-agent")?.contains("Chrome") == true)
	}

	// MARK: - Helpers

	private static func response(_ code: Int, for request: URLRequest) -> HTTPURLResponse {
		HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1",
		                headerFields: ["Content-Type": "application/json"])!
	}

	private func assertThrows(_ expected: ClaudeAPIError,
	                          file: StaticString = #filePath,
	                          line: UInt = #line,
	                          _ block: () async throws -> Void) async {
		do {
			try await block()
			XCTFail("expected \(expected), no throw", file: file, line: line)
		} catch let error as ClaudeAPIError {
			XCTAssertEqual(String(describing: error), String(describing: expected), file: file, line: line)
		} catch {
			XCTFail("unexpected error: \(error)", file: file, line: line)
		}
	}
}

// MARK: - URLProtocol stub

private final class StubURLProtocol: URLProtocol {
	nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
	nonisolated(unsafe) static var lastRequest: URLRequest?

	override class func canInit(with request: URLRequest) -> Bool { true }
	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		Self.lastRequest = request
		guard let handler = Self.handler else {
			client?.urlProtocolDidFinishLoading(self)
			return
		}
		do {
			let (response, data) = try handler(request)
			client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
			client?.urlProtocol(self, didLoad: data)
			client?.urlProtocolDidFinishLoading(self)
		} catch {
			client?.urlProtocol(self, didFailWithError: error)
		}
	}

	override func stopLoading() {}
}
