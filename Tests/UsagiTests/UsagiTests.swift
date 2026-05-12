import XCTest
@testable import Usagi

/// These exist mostly as an early-warning system: if claude.ai changes the shape
/// of its (unofficial) usage endpoints, or the session-window math, the failing
/// test names tell you exactly what broke.
final class UsagiTests: XCTestCase {

	private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
		try ClaudeAPIClient.makeDecoder().decode(T.self, from: Data(json.utf8))
	}

	// MARK: - GET /organizations/{id}/usage

	func testUsageSnapshotFull() throws {
		// `five_hour` exercises the fractional-seconds date path; `seven_day` the plain one.
		let snap = try decode(UsageSnapshot.self, """
		{
		  "five_hour": { "utilization": 76.4, "resets_at": "2026-05-12T18:00:00.123Z" },
		  "seven_day": { "utilization": 20, "resets_at": "2026-05-18T09:30:00Z" },
		  "seven_day_opus": null
		}
		""")
		XCTAssertEqual(snap.fiveHour?.utilization, 76.4)
		XCTAssertEqual(snap.sevenDay?.utilization, 20)
		XCTAssertNil(snap.sevenDayOpus)

		let iso = ISO8601DateFormatter()
		XCTAssertEqual(snap.sevenDay?.resetsAt, iso.date(from: "2026-05-18T09:30:00Z"))
		iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		XCTAssertEqual(snap.fiveHour?.resetsAt, iso.date(from: "2026-05-12T18:00:00.123Z"))
	}

	func testUsageSnapshotAllNull() throws {
		let snap = try decode(UsageSnapshot.self, #"{ "five_hour": null, "seven_day": null, "seven_day_opus": null }"#)
		XCTAssertNil(snap.fiveHour)
		XCTAssertNil(snap.sevenDay)
		XCTAssertNil(snap.sevenDayOpus)
	}

	func testUsageSnapshotToleratesUnknownKeys() throws {
		// Forward-compat: a new window/field Anthropic adds must not break decoding.
		let snap = try decode(UsageSnapshot.self, """
		{
		  "five_hour": { "utilization": 5, "resets_at": "2026-05-12T18:00:00Z", "limit_tokens": 999 },
		  "seven_day": null,
		  "seven_day_opus": null,
		  "some_future_window": { "utilization": 1, "resets_at": null }
		}
		""")
		XCTAssertEqual(snap.fiveHour?.utilization, 5)
		XCTAssertNotNil(snap.fiveHour?.resetsAt)
	}

	func testWindowWithoutResetsAt() throws {
		let snap = try decode(UsageSnapshot.self, #"{ "five_hour": { "utilization": 12 }, "seven_day": null, "seven_day_opus": null }"#)
		XCTAssertEqual(snap.fiveHour?.utilization, 12)
		XCTAssertNil(snap.fiveHour?.resetsAt)
	}

	// MARK: - GET /organizations/{id}/overage_spend_limit

	func testOverageDecodingAndUtilization() throws {
		let o = try decode(OverageSpend.self, #"{ "monthly_credit_limit": 2000, "used_credits": 815, "currency": "EUR", "is_enabled": true }"#)
		XCTAssertTrue(o.isEnabled)
		XCTAssertEqual(o.currency, "EUR")
		XCTAssertEqual(o.utilization, 40.75, accuracy: 0.0001)
	}

	func testOverageUtilizationEdges() {
		XCTAssertEqual(OverageSpend(monthlyCreditLimit: 0, usedCredits: 50, currency: "USD", isEnabled: true).utilization, 0)
		XCTAssertEqual(OverageSpend(monthlyCreditLimit: 100, usedCredits: 250, currency: "USD", isEnabled: true).utilization, 100)
	}

	// MARK: - session "time remaining" math

	func testRemainingFraction() {
		let now = Date(timeIntervalSince1970: 1_000_000)
		let w: TimeInterval = 5 * 3600
		XCTAssertEqual(AppState.remainingFraction(resetsAt: now.addingTimeInterval(w),     now: now, window: w), 1,   accuracy: 0.0001)
		XCTAssertEqual(AppState.remainingFraction(resetsAt: now.addingTimeInterval(w / 2), now: now, window: w), 0.5, accuracy: 0.0001)
		XCTAssertEqual(AppState.remainingFraction(resetsAt: now.addingTimeInterval(-60),   now: now, window: w), 0)            // already past
		XCTAssertEqual(AppState.remainingFraction(resetsAt: now.addingTimeInterval(w * 2), now: now, window: w), 1)            // clamped
		XCTAssertEqual(AppState.remainingFraction(resetsAt: nil,                            now: now, window: w), 1)            // no reset yet → full
	}

	// MARK: - relative-time formatting (used in the menu)

	func testRelativeShort() {
		let now = Date(timeIntervalSince1970: 1_000_000)
		XCTAssertEqual(now.addingTimeInterval(30).relativeShort(reference: now), "in < 1m")
		XCTAssertEqual(now.addingTimeInterval(47 * 60).relativeShort(reference: now), "in 47m")
		XCTAssertEqual(now.addingTimeInterval(3 * 3600 + 12 * 60).relativeShort(reference: now), "in 3h 12m")
		XCTAssertEqual(now.addingTimeInterval(2 * 3600).relativeShort(reference: now), "in 2h")
		XCTAssertEqual(now.addingTimeInterval(3 * 86400 + 14 * 3600).relativeShort(reference: now), "in 3d 14h")
		XCTAssertEqual(now.addingTimeInterval(-90).relativeShort(reference: now), "1m ago")
	}
}
