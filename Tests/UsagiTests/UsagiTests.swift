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

	// MARK: - status-icon colour thresholds

	func testGaugeLevelThresholds() {
		XCTAssertEqual(GaugeLevel.forUsage(0),    .nominal)
		XCTAssertEqual(GaugeLevel.forUsage(0.49), .nominal)
		XCTAssertEqual(GaugeLevel.forUsage(0.5),  .elevated)
		XCTAssertEqual(GaugeLevel.forUsage(0.74), .elevated)
		XCTAssertEqual(GaugeLevel.forUsage(0.75), .high)
		XCTAssertEqual(GaugeLevel.forUsage(0.89), .high)
		XCTAssertEqual(GaugeLevel.forUsage(0.9),  .critical)
		XCTAssertEqual(GaugeLevel.forUsage(1.0),  .critical)
		XCTAssertEqual(GaugeLevel.forUsage(2.0),  .critical)   // over-consumed still reads critical
	}

	func testDialUrgencyThresholds() {
		XCTAssertEqual(DialUrgency.forRemaining(nil),   .calm)   // no active window
		XCTAssertEqual(DialUrgency.forRemaining(1.0),   .calm)
		XCTAssertEqual(DialUrgency.forRemaining(0.10),  .calm)   // ~30 min → still calm
		XCTAssertEqual(DialUrgency.forRemaining(0.09),  .soon)
		XCTAssertEqual(DialUrgency.forRemaining(0.033), .soon)   // ~10 min → soon
		XCTAssertEqual(DialUrgency.forRemaining(0.02),  .imminent)
		XCTAssertEqual(DialUrgency.forRemaining(0.0),   .imminent)
	}

	// MARK: - countdown label

	func testCountdownLabel() {
		let now = Date(timeIntervalSince1970: 2_000_000)
		XCTAssertEqual(AppState.countdownLabel(resetsAt: now.addingTimeInterval(3 * 3600 + 12 * 60), now: now), "3h")  // floors to the hour
		XCTAssertEqual(AppState.countdownLabel(resetsAt: now.addingTimeInterval(3600), now: now), "1h")
		XCTAssertEqual(AppState.countdownLabel(resetsAt: now.addingTimeInterval(42 * 60), now: now), "42m")
		XCTAssertEqual(AppState.countdownLabel(resetsAt: now.addingTimeInterval(30), now: now), "1m")                  // floors up to "1m"
		XCTAssertNil(AppState.countdownLabel(resetsAt: now.addingTimeInterval(-10), now: now))                          // already reset
		XCTAssertNil(AppState.countdownLabel(resetsAt: nil, now: now))
	}
}

/// Touches `AppState`, so it runs on the main actor.
@MainActor
final class AppStateMenuBarTests: XCTestCase {

	func testNoSessionGaugeOutsideReady() {
		let s = AppState()
		s.snapshot = UsageSnapshot(fiveHour: UsageWindow(utilization: 50, resetsAt: Date()), sevenDay: nil, sevenDayOpus: nil)
		for phase: AppState.Phase in [.bootstrapping, .loading, .signedOut, .error("nope")] {
			s.phase = phase
			XCTAssertNil(s.menuBarPercent, "\(phase)")
			XCTAssertNil(s.sessionUsageFraction, "\(phase)")
			XCTAssertNil(s.sessionTimeRemainingFraction, "\(phase)")
			XCTAssertNil(s.menuBarCountdown, "\(phase)")
		}
	}

	func testReadyWithSessionWindow() {
		let s = AppState()
		s.snapshot = UsageSnapshot(
			fiveHour: UsageWindow(utilization: 76.4, resetsAt: Date(timeIntervalSinceNow: 2.5 * 3600)),
			sevenDay: nil, sevenDayOpus: nil)
		s.phase = .ready
		XCTAssertEqual(s.menuBarPercent, "76%")
		XCTAssertEqual(s.sessionUsageFraction ?? -1, 0.764, accuracy: 0.0001)
		XCTAssertEqual(s.sessionTimeRemainingFraction ?? -1, 0.5, accuracy: 0.01)
		XCTAssertEqual(s.menuBarCountdown, "2h")
	}

	func testReadyClampsOverConsumed() {
		let s = AppState()
		s.snapshot = UsageSnapshot(fiveHour: UsageWindow(utilization: 137, resetsAt: nil), sevenDay: nil, sevenDayOpus: nil)
		s.phase = .ready
		XCTAssertEqual(s.menuBarPercent, "137%")              // label stays exact
		XCTAssertEqual(s.sessionUsageFraction, 1.0)           // bar fraction is clamped
		XCTAssertEqual(s.sessionTimeRemainingFraction, 1.0)   // no resets_at → treated as full
		XCTAssertNil(s.menuBarCountdown)                       // …and no countdown without resets_at
	}

	func testReadyButNoSessionWindow() {
		let s = AppState()
		s.snapshot = UsageSnapshot(fiveHour: nil, sevenDay: UsageWindow(utilization: 20, resetsAt: nil), sevenDayOpus: nil)
		s.phase = .ready
		XCTAssertNil(s.menuBarPercent)
		XCTAssertNil(s.sessionUsageFraction)
		XCTAssertNil(s.sessionTimeRemainingFraction)
	}

	func testRestoringSavedRefreshIntervalDoesNotCrash() {
		// Regression: refreshInterval's didSet fires during init when restoring a
		// persisted value (because @Observable), before the refresher exists.
		let key = "ie.duggan.usagi.refreshInterval"
		let saved = UserDefaults.standard.object(forKey: key)
		defer {
			if let saved { UserDefaults.standard.set(saved, forKey: key) }
			else { UserDefaults.standard.removeObject(forKey: key) }
		}
		UserDefaults.standard.set(30.0, forKey: key)
		_ = AppState()                                        // must not trap
		UserDefaults.standard.set(45.0, forKey: key)          // not one of 5/30/300 → snaps to nearest
		XCTAssertEqual(AppState().refreshInterval, 30)
	}
}
