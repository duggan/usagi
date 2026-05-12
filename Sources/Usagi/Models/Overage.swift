import Foundation

/// Response from `/organizations/{id}/overage_spend_limit`.
/// Returns 404 (or similar) when the user hasn't enabled overage spending.
struct OverageSpend: Codable, Hashable {
	let monthlyCreditLimit: Double
	let usedCredits: Double
	let currency: String
	let isEnabled: Bool

	enum CodingKeys: String, CodingKey {
		case monthlyCreditLimit = "monthly_credit_limit"
		case usedCredits = "used_credits"
		case currency
		case isEnabled = "is_enabled"
	}

	/// 0–100.
	var utilization: Double {
		guard monthlyCreditLimit > 0 else { return 0 }
		return min(100, (usedCredits / monthlyCreditLimit) * 100)
	}
}
