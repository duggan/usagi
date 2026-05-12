import SwiftUI

struct UsageBarsView: View {
	let snapshot: UsageSnapshot
	let overage: OverageSpend?
	var showPercent: Bool = true

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			if let session = snapshot.fiveHour {
				UsageRow(
					label: "5-hour session",
					utilization: session.utilization,
					detail: resetDetail(session.resetsAt, prefix: "Resets"),
					tint: Palette.session,
					showPercent: showPercent
				)
			}

			if let weekly = snapshot.sevenDay {
				UsageRow(
					label: "Weekly",
					utilization: weekly.utilization,
					detail: resetDetail(weekly.resetsAt, prefix: "Resets"),
					tint: Palette.weekly,
					showPercent: showPercent
				)
			}

			if let overage, overage.isEnabled {
				OverageRow(overage: overage)
			}
		}
	}

	private func resetDetail(_ date: Date?, prefix: String) -> String? {
		guard let date else { return nil }
		return "\(prefix) \(date.relativeShort())"
	}
}

struct OverageRow: View {
	let overage: OverageSpend

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				Text("Extra Usage")
					.font(.system(size: 12, weight: .medium))
				Spacer()
				Text("\(formatted(overage.usedCredits)) / \(formatted(overage.monthlyCreditLimit))")
					.font(.system(size: 12, weight: .semibold).monospacedDigit())
					.foregroundStyle(Palette.overage)
			}
			ProgressBar(fraction: overage.utilization / 100, tint: Palette.overage)
		}
	}

	/// API delivers amounts in cents; convert to major units for display.
	private func formatted(_ cents: Double) -> String {
		let f = NumberFormatter()
		f.numberStyle = .currency
		f.currencyCode = overage.currency
		f.maximumFractionDigits = 2
		return f.string(from: NSNumber(value: cents / 100)) ?? String(format: "%.2f", cents / 100)
	}
}
