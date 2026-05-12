import Foundation

enum ClaudeAPIError: Error, LocalizedError {
	case unauthorized
	case noSessionKey
	case noOrganization
	case http(Int)
	case decoding(path: String, detail: String)
	case transport(Error)

	var errorDescription: String? {
		switch self {
		case .unauthorized: "Session expired — sign in again"
		case .noSessionKey: "Not signed in"
		case .noOrganization: "No organisations on this account"
		case .http(let code): "Claude API returned \(code)"
		case .decoding(let path, let detail): "Decode failed at \(path): \(detail)"
		case .transport(let err): err.localizedDescription
		}
	}
}

/// Pretty-formats a DecodingError so we can see *which* key/path is wrong.
private func describe(_ error: Error) -> (path: String, detail: String) {
	guard let decErr = error as? DecodingError else {
		return ("?", error.localizedDescription)
	}
	switch decErr {
	case .keyNotFound(let key, let ctx):
		let path = (ctx.codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: ".")
		return (path.isEmpty ? key.stringValue : path, "key not found")
	case .valueNotFound(_, let ctx):
		let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
		return (path.isEmpty ? "<root>" : path, "value not found — \(ctx.debugDescription)")
	case .typeMismatch(let type, let ctx):
		let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
		return (path.isEmpty ? "<root>" : path, "expected \(type) — \(ctx.debugDescription)")
	case .dataCorrupted(let ctx):
		let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
		return (path.isEmpty ? "<root>" : path, "data corrupted — \(ctx.debugDescription)")
	@unknown default:
		return ("?", error.localizedDescription)
	}
}

actor ClaudeAPIClient {
	static let baseURL = URL(string: "https://claude.ai/api")!

	private let session: URLSession
	private let decoder: JSONDecoder

	init(session: URLSession = .shared) {
		self.session = session
		self.decoder = Self.makeDecoder()
	}

	/// The decoder used for every endpoint — ISO8601 with or without fractional
	/// seconds. Exposed so tests can decode fixtures through the real config.
	static func makeDecoder() -> JSONDecoder {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .custom { decoder in
			let container = try decoder.singleValueContainer()
			let str = try container.decode(String.self)
			let formatter = ISO8601DateFormatter()
			formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
			if let date = formatter.date(from: str) {
				return date
			}
			formatter.formatOptions = [.withInternetDateTime]
			if let date = formatter.date(from: str) {
				return date
			}
			throw DecodingError.dataCorruptedError(in: container,
				debugDescription: "Unparseable ISO8601 date: \(str)")
		}
		return decoder
	}

	// MARK: - Endpoints

	func organizations(sessionKey: String) async throws -> [Organization] {
		try await get(path: "/organizations", sessionKey: sessionKey)
	}

	func usage(sessionKey: String, organizationID: String) async throws -> UsageSnapshot {
		try await get(path: "/organizations/\(organizationID)/usage", sessionKey: sessionKey)
	}

	/// Returns nil if the user hasn't enabled overage spend (404).
	func overage(sessionKey: String, organizationID: String) async throws -> OverageSpend? {
		do {
			return try await get(path: "/organizations/\(organizationID)/overage_spend_limit",
			                     sessionKey: sessionKey)
		} catch ClaudeAPIError.http(404) {
			return nil
		}
	}

	// MARK: - Internal

	private func get<T: Decodable>(path: String, sessionKey: String) async throws -> T {
		guard !sessionKey.isEmpty else { throw ClaudeAPIError.noSessionKey }

		var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
		request.httpMethod = "GET"
		request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		request.setValue("usagi/\(AppVersion.short)", forHTTPHeaderField: "User-Agent")

		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await session.data(for: request)
		} catch {
			throw ClaudeAPIError.transport(error)
		}

		guard let http = response as? HTTPURLResponse else {
			throw ClaudeAPIError.http(0)
		}

		switch http.statusCode {
		case 200..<300:
			break
		case 401, 403:
			throw ClaudeAPIError.unauthorized
		default:
			throw ClaudeAPIError.http(http.statusCode)
		}

		do {
			return try decoder.decode(T.self, from: data)
		} catch {
			let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<non-utf8>"
			NSLog("usagi: decode failed for %@\nresponse:\n%@", path, preview)
			let (p, d) = describe(error)
			throw ClaudeAPIError.decoding(path: p, detail: d)
		}
	}
}
