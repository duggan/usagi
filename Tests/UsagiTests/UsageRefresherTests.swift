import XCTest
@testable import Usagi

/// Exercises the pure backoff math. The scheduling layer itself uses
/// `DispatchQueue.main.asyncAfter` which is awkward to test reliably; the
/// extracted `delay(...)` function lets us cover the table exhaustively.
final class UsageRefresherTests: XCTestCase {

	func testZeroFailuresIsBaseInterval() {
		XCTAssertEqual(UsageRefresher.delay(consecutiveFailures: 0, baseInterval: 30), 30)
		XCTAssertEqual(UsageRefresher.delay(consecutiveFailures: 0, baseInterval: 5), 5)
	}

	func testExponentialBackoffMultipliers() {
		// 1×, 2×, 4×, 8×, 16×, 32×, 64×
		let base: TimeInterval = 10
		XCTAssertEqual(UsageRefresher.delay(consecutiveFailures: 0, baseInterval: base), 10)
		XCTAssertEqual(UsageRefresher.delay(consecutiveFailures: 1, baseInterval: base), 20)
		XCTAssertEqual(UsageRefresher.delay(consecutiveFailures: 2, baseInterval: base), 40)
		XCTAssertEqual(UsageRefresher.delay(consecutiveFailures: 3, baseInterval: base), 80)
		XCTAssertEqual(UsageRefresher.delay(consecutiveFailures: 4, baseInterval: base), 160)
		XCTAssertEqual(UsageRefresher.delay(consecutiveFailures: 5, baseInterval: base), 320)
		XCTAssertEqual(UsageRefresher.delay(consecutiveFailures: 6, baseInterval: base), 640)
	}

	func testFailureCountClampsAt6() {
		// Inputs above 6 don't push the multiplier higher.
		let base: TimeInterval = 10
		let cap = UsageRefresher.delay(consecutiveFailures: 6, baseInterval: base)
		XCTAssertEqual(UsageRefresher.delay(consecutiveFailures: 7, baseInterval: base), cap)
		XCTAssertEqual(UsageRefresher.delay(consecutiveFailures: 50, baseInterval: base), cap)
	}

	func testNegativeFailuresClampToBase() {
		// Defensive: a hypothetical negative value shouldn't underflow the shift.
		XCTAssertEqual(UsageRefresher.delay(consecutiveFailures: -1, baseInterval: 30), 30)
	}

	func testCeilingAt30Minutes() {
		// 60s × 64 = 3840s, but capped at 1800s.
		XCTAssertEqual(UsageRefresher.delay(consecutiveFailures: 6, baseInterval: 60),
		               UsageRefresher.maxDelay)
		// A huge base hits the cap immediately at 0 failures.
		XCTAssertEqual(UsageRefresher.delay(consecutiveFailures: 0, baseInterval: 10_000),
		               UsageRefresher.maxDelay)
	}

	func testMaxDelayIsThirtyMinutes() {
		XCTAssertEqual(UsageRefresher.maxDelay, 30 * 60)
	}
}
