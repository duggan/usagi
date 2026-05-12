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

/// Top-level response from `/organizations/{id}/usage`. Each window can be
/// null on accounts where it doesn't apply (e.g. `seven_day_opus` on plans
/// without Opus access).
struct UsageSnapshot: Codable, Hashable {
	let fiveHour: UsageWindow?
	let sevenDay: UsageWindow?
	let sevenDayOpus: UsageWindow?

	enum CodingKeys: String, CodingKey {
		case fiveHour = "five_hour"
		case sevenDay = "seven_day"
		case sevenDayOpus = "seven_day_opus"
	}
}
