import Foundation

/// Periodically calls a tick handler. Replaces its timer when the interval changes.
@MainActor
final class UsageRefresher {
	private var timer: Timer?
	private let tick: () async -> Void

	init(tick: @escaping () async -> Void) {
		self.tick = tick
	}

	func start(interval: TimeInterval) {
		stop()
		let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [tick] _ in
			Task { await tick() }
		}
		RunLoop.main.add(timer, forMode: .common)
		self.timer = timer
	}

	func update(interval: TimeInterval) {
		guard timer != nil else { return }
		start(interval: interval)
	}

	func stop() {
		timer?.invalidate()
		timer = nil
	}
}
