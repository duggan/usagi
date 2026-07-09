import SwiftUI

struct UsageBarsView: View {
	let snapshot: UsageSnapshot
	let overage: OverageSpend?
	var showPercent: Bool = true

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			UsageRow(
				label: "5-hour session",
				utilization: snapshot.fiveHour.utilization,
				detail: resetDetail(snapshot.fiveHour.resetsAt, prefix: "Resets"),
				tint: Palette.session,
				showPercent: showPercent
			)

			if let weekly = snapshot.sevenDay {
				let scoped = snapshot.weeklyScopedLimits

				VStack(alignment: .leading, spacing: 6) {
					// The reset caption is hoisted out of UsageRow and rendered below
					// the sub-bars: the per-model caps reset on the same schedule, and
					// a caption wedged between them would orphan them from the weekly
					// bar they belong to.
					UsageRow(
						label: "Weekly",
						utilization: weekly.utilization,
						detail: scoped.isEmpty ? resetDetail(weekly.resetsAt, prefix: "Resets") : nil,
						tint: Palette.weekly,
						showPercent: showPercent
					)

					// Each scoped cap is a share of its own limit, not of the weekly
					// total, so it gets its own track rather than a segment of the
					// weekly bar.
					ForEach(scoped, id: \.self) { limit in
						if let name = limit.scopeLabel {
							ScopedUsageRow(
								label: name,
								utilization: limit.percent,
								tint: Palette.scope(name),
								showPercent: showPercent
							)
						}
					}

					if !scoped.isEmpty, let detail = resetDetail(weekly.resetsAt, prefix: "Resets") {
						Text(detail)
							.font(.system(size: 10))
							.foregroundStyle(Palette.dim)
					}
				}
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

/// A per-model weekly cap, rendered as an indented, thinner bar beneath the
/// weekly row it belongs to.
struct ScopedUsageRow: View {
	let label: String
	let utilization: Double
	let tint: Color
	var showPercent: Bool = true

	var body: some View {
		VStack(alignment: .leading, spacing: 3) {
			HStack {
				Text(label)
					.font(.system(size: 11))
					.foregroundStyle(Palette.dim)
				Spacer()
				if showPercent {
					Text("\(Int(utilization.rounded()))%")
						.font(.system(size: 11, weight: .medium).monospacedDigit())
						.foregroundStyle(tint)
				}
			}
			ProgressBar(fraction: utilization / 100, tint: tint, height: 4)
		}
		.padding(.leading, 12)
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
