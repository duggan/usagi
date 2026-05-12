import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class AppState {
	enum Phase: Equatable {
		case bootstrapping
		case signedOut
		case loading
		case ready
		case error(String)
	}

	// MARK: - Public state

	var phase: Phase = .bootstrapping
	var organization: Organization? = nil
	var snapshot: UsageSnapshot? = nil
	var overage: OverageSpend? = nil
	var lastRefresh: Date? = nil
	var refreshInterval: TimeInterval = 30 {
		didSet {
			UserDefaults.standard.set(refreshInterval, forKey: Self.refreshIntervalKey)
			refresher.update(interval: refreshInterval)
		}
	}

	/// Notifies observers when the value the menu bar shows might have changed.
	/// SwiftUI views observe state directly; the AppDelegate uses this to redraw the status item.
	var menuBarTick: Int = 0

	// MARK: - Dependencies

	@ObservationIgnored private let api: ClaudeAPIClient
	@ObservationIgnored private let auth: AuthCoordinator
	@ObservationIgnored private var refresher: UsageRefresher!

	// MARK: - Init

	init(api: ClaudeAPIClient = ClaudeAPIClient(), auth: AuthCoordinator? = nil) {
		self.api = api
		self.auth = auth ?? AuthCoordinator()
		if let stored = UserDefaults.standard.object(forKey: Self.refreshIntervalKey) as? TimeInterval {
			self.refreshInterval = max(15, min(300, stored))
		}
		self.refresher = UsageRefresher { [weak self] in
			await self?.refresh()
		}
	}

	// MARK: - Lifecycle

	func load() async {
		if SessionStore.read() != nil {
			phase = .loading
			await refresh()
			refresher.start(interval: refreshInterval)
		} else {
			phase = .signedOut
		}
	}

	func presentSignIn() {
		auth.presentLogin { [weak self] _ in
			Task { @MainActor [weak self] in
				guard let self else { return }
				self.phase = .loading
				await self.refresh()
				self.refresher.start(interval: self.refreshInterval)
			}
		}
	}

	func signOut() {
		refresher.stop()
		SessionStore.delete()
		Task { await AuthCoordinator.clearWebData() }
		organization = nil
		snapshot = nil
		overage = nil
		lastRefresh = nil
		phase = .signedOut
		menuBarTick &+= 1
	}

	// MARK: - Refresh

	func refresh() async {
		guard let key = SessionStore.read() else {
			phase = .signedOut
			menuBarTick &+= 1
			return
		}

		do {
			let org: Organization
			if let cached = organization {
				org = cached
			} else {
				let orgs = try await api.organizations(sessionKey: key)
				guard let first = orgs.first else { throw ClaudeAPIError.noOrganization }
				org = first
				organization = first
			}

			async let usageReq = api.usage(sessionKey: key, organizationID: org.uuid)
			async let overageReq = api.overage(sessionKey: key, organizationID: org.uuid)

			let usage = try await usageReq
			let overageValue = try? await overageReq

			snapshot = usage
			overage = overageValue
			lastRefresh = Date()
			phase = .ready
			if let fh = usage.fiveHour {
				let secs = fh.resetsAt?.timeIntervalSinceNow
				NSLog("usagi: five_hour util=%.1f resets_at=%@ (in %@s) → remaining=%@",
				      fh.utilization,
				      fh.resetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "nil",
				      secs.map { String(format: "%.0f", $0) } ?? "nil",
				      sessionTimeRemainingFraction.map { String(format: "%.3f", $0) } ?? "nil")
			} else {
				NSLog("usagi: five_hour = nil")
			}
		} catch ClaudeAPIError.unauthorized {
			signOut()
		} catch {
			phase = .error(error.localizedDescription)
		}
		menuBarTick &+= 1
	}

	// MARK: - Menu bar gauge

	/// Length of the rolling session window. The API only reports `resets_at`,
	/// so we infer "time remaining" against this assumed span.
	static let sessionWindow: TimeInterval = 5 * 3600

	private var activeSession: UsageWindow? {
		guard phase == .ready else { return nil }
		return snapshot?.fiveHour
	}

	/// Precise session utilization for the status-item title, e.g. `"42%"`.
	var menuBarPercent: String? {
		activeSession.map { "\(Int($0.utilization.rounded()))%" }
	}

	/// 0…1 — fraction of the session quota used. `nil` when there's no active window.
	var sessionUsageFraction: Double? {
		activeSession.map { min(1, max(0, $0.utilization / 100)) }
	}

	/// 0…1 — fraction of the 5-hour window still remaining (drains toward reset).
	/// `nil` when there's no active window. An active window that hasn't announced
	/// a `resets_at` yet (e.g. just opened) is treated as full.
	var sessionTimeRemainingFraction: Double? {
		guard let session = activeSession else { return nil }
		guard let resetsAt = session.resetsAt else { return 1 }
		return min(1, max(0, resetsAt.timeIntervalSinceNow / Self.sessionWindow))
	}

	/// Compact time-until-reset for the countdown dial, e.g. `"3h"` or `"42m"`
	/// (single largest unit, never below `"1m"`). `nil` when there's no active
	/// window or no `resets_at`.
	var menuBarCountdown: String? {
		guard let resetsAt = activeSession?.resetsAt else { return nil }
		let secs = resetsAt.timeIntervalSinceNow
		guard secs > 0 else { return nil }
		if secs >= 3600 { return "\(Int(secs / 3600))h" }
		return "\(max(1, Int(secs / 60)))m"
	}

	// MARK: - Storage keys

	private static let refreshIntervalKey = "ie.duggan.usagi.refreshInterval"
}
