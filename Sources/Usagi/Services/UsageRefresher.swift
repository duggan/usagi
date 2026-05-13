import Foundation

/// Periodically calls a tick handler on a fixed interval, but backs off
/// exponentially (doubling, capped) while ticks keep failing — so a degraded
/// or angry endpoint doesn't get hammered. A success resets to the base interval.
@MainActor
final class UsageRefresher {
	/// Returns `true` if the tick succeeded.
	private let tick: () async -> Bool

	private var interval: TimeInterval = 30
	private var running = false
	/// Bumped by every `start()`/`stop()`; a pending callback whose generation
	/// no longer matches simply bails, which is how we cancel without timers.
	private var generation = 0
	private var consecutiveFailures = 0

	/// Never wait longer than this between ticks, however long the backoff gets.
	nonisolated static let maxDelay: TimeInterval = 30 * 60

	/// Pure backoff math: 0 failures → base, then 2×, 4×, …, 64× (capped at 6 failures),
	/// finally clamped to `maxDelay`.
	nonisolated static func delay(consecutiveFailures: Int, baseInterval: TimeInterval) -> TimeInterval {
		let capped = min(max(consecutiveFailures, 0), 6)
		let multiplier = capped == 0 ? 1.0 : Double(1 << capped)
		return min(baseInterval * multiplier, maxDelay)
	}

	init(tick: @escaping () async -> Bool) {
		self.tick = tick
	}

	func start(interval: TimeInterval) {
		self.interval = interval
		consecutiveFailures = 0
		running = true
		generation &+= 1
		schedule(generation, after: interval)
	}

	/// Restart with a new base interval (no-op if not currently running).
	func update(interval: TimeInterval) {
		guard running else { return }
		start(interval: interval)
	}

	func stop() {
		running = false
		generation &+= 1
	}

	private func schedule(_ gen: Int, after delay: TimeInterval) {
		DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
			Task { @MainActor [weak self] in
				guard let self, self.running, self.generation == gen else { return }
				let ok = await self.tick()
				// `tick()` may have triggered stop()/start() (e.g. sign-out); if so, don't reschedule.
				guard self.running, self.generation == gen else { return }
				self.consecutiveFailures = ok ? 0 : min(self.consecutiveFailures + 1, 6)
				self.schedule(gen, after: Self.delay(consecutiveFailures: self.consecutiveFailures,
				                                    baseInterval: self.interval))
			}
		}
	}
}
