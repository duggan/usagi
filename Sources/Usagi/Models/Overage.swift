import Foundation

/// Response from `/organizations/{id}/overage_spend_limit`.
/// Returns 404 (or similar) when the user hasn't enabled overage spending.
///
/// The live API has shifted field names — `monthly_credit_limit` is the legacy
/// name; newer responses use `monthly_limit`. `used_credits` may decode as an
/// integer or a JSON float (e.g. `21.0`). Both shapes are accepted here so a
/// silent rename doesn't blank the Extra Usage row.
struct OverageSpend: Codable, Hashable {
	let monthlyCreditLimit: Double
	let usedCredits: Double
	let currency: String
	let isEnabled: Bool

	init(monthlyCreditLimit: Double, usedCredits: Double, currency: String, isEnabled: Bool) {
		self.monthlyCreditLimit = monthlyCreditLimit
		self.usedCredits = usedCredits
		self.currency = currency
		self.isEnabled = isEnabled
	}

	private enum CodingKeys: String, CodingKey {
		case monthlyLimit = "monthly_limit"
		case monthlyCreditLimit = "monthly_credit_limit"
		case usedCredits = "used_credits"
		case currency
		case isEnabled = "is_enabled"
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		let limit = try c.decodeIfPresent(Double.self, forKey: .monthlyLimit)
			?? c.decodeIfPresent(Double.self, forKey: .monthlyCreditLimit)
			?? 0
		let used = try c.decodeIfPresent(Double.self, forKey: .usedCredits) ?? 0
		let currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
		// If the server omits `is_enabled`, treat a non-zero limit as enabled.
		let enabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? (limit > 0)
		self.monthlyCreditLimit = limit
		self.usedCredits = used
		self.currency = currency
		self.isEnabled = enabled
	}

	func encode(to encoder: Encoder) throws {
		var c = encoder.container(keyedBy: CodingKeys.self)
		try c.encode(monthlyCreditLimit, forKey: .monthlyCreditLimit)
		try c.encode(usedCredits, forKey: .usedCredits)
		try c.encode(currency, forKey: .currency)
		try c.encode(isEnabled, forKey: .isEnabled)
	}

	/// 0–100.
	var utilization: Double {
		guard monthlyCreditLimit > 0 else { return 0 }
		return min(100, (usedCredits / monthlyCreditLimit) * 100)
	}
}
