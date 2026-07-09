import Foundation

struct UsageWindow: Codable, Hashable {
	/// 0–100.
	let utilization: Double
	let resetsAt: Date?

	enum CodingKeys: String, CodingKey {
		case utilization
		case resetsAt = "resets_at"
	}
}

/// One entry of the `limits` array. Per-model weekly caps arrive here rather
/// than as a top-level `seven_day_<model>` window: they're `kind == "weekly_scoped"`
/// with the model named in `scope.model.display_name`.
///
/// `percent` is measured against *this* limit's own cap, so a scoped limit is
/// not a slice of `weekly_all` — the two aren't summable.
struct UsageLimit: Codable, Hashable {
	let group: String?
	let kind: String?
	/// 0–100.
	let percent: Double
	let resetsAt: Date?
	let scope: Scope?

	/// A limit can be scoped by model ("Fable") or by surface (where the usage
	/// happened). Only `model` has ever been observed populated; `surface` has
	/// always been null, so its encoding is unconfirmed — `ScopeName` accepts
	/// either a bare string or a `{ display_name }` object to cover both.
	struct Scope: Codable, Hashable {
		let model: ScopeName?
		let surface: ScopeName?

		/// The human-readable thing this limit is scoped to, model taking priority.
		var displayName: String? {
			[model?.displayName, surface?.displayName]
				.compactMap { $0 }
				.first { !$0.isEmpty }
		}
	}

	struct ScopeName: Codable, Hashable {
		let displayName: String?

		enum CodingKeys: String, CodingKey {
			case displayName = "display_name"
		}

		init(displayName: String?) {
			self.displayName = displayName
		}

		init(from decoder: Decoder) throws {
			if let single = try? decoder.singleValueContainer(), let raw = try? single.decode(String.self) {
				self.displayName = raw
				return
			}
			let container = try decoder.container(keyedBy: CodingKeys.self)
			self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
		}
	}

	enum CodingKeys: String, CodingKey {
		case group, kind, percent, scope
		case resetsAt = "resets_at"
	}

	/// Label for a scoped weekly cap — the model, else the surface, else a
	/// generic fallback. Never nil for a `weekly_scoped` limit: a scope shape we
	/// don't recognise must still render a bar rather than vanish from the UI.
	var scopeLabel: String? {
		guard kind == "weekly_scoped" else { return nil }
		return scope?.displayName ?? "Other"
	}
}

/// Top-level response from `/organizations/{id}/usage`. Each window can be
/// null on accounts where it doesn't apply (e.g. `seven_day_opus` on plans
/// without Opus access).
struct UsageSnapshot: Codable, Hashable {
	let fiveHour: UsageWindow
	let sevenDay: UsageWindow?
	let sevenDayOpus: UsageWindow?
	let sevenDaySonnet: UsageWindow?
	let limits: [UsageLimit]?

	init(
		fiveHour: UsageWindow,
		sevenDay: UsageWindow?,
		sevenDayOpus: UsageWindow?,
		sevenDaySonnet: UsageWindow?,
		limits: [UsageLimit]? = nil
	) {
		self.fiveHour = fiveHour
		self.sevenDay = sevenDay
		self.sevenDayOpus = sevenDayOpus
		self.sevenDaySonnet = sevenDaySonnet
		self.limits = limits
	}

	/// Scoped weekly caps (e.g. Fable), in the order the API returned them.
	var weeklyScopedLimits: [UsageLimit] {
		(limits ?? []).filter { $0.group == "weekly" && $0.scopeLabel != nil }
	}

	enum CodingKeys: String, CodingKey {
		case fiveHour = "five_hour"
		case sevenDay = "seven_day"
		case sevenDayOpus = "seven_day_opus"
		case sevenDaySonnet = "seven_day_sonnet"
		case limits
	}
}
