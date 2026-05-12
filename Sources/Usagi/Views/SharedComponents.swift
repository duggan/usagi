import SwiftUI

struct UsageRow: View {
	let label: String
	let utilization: Double
	let detail: String?
	let tint: Color

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				Text(label)
					.font(.system(size: 12, weight: .medium))
				Spacer()
				Text("\(Int(utilization.rounded()))%")
					.font(.system(size: 12, weight: .semibold).monospacedDigit())
					.foregroundStyle(tint)
			}
			ProgressBar(fraction: utilization / 100, tint: tint)
			if let detail {
				Text(detail)
					.font(.system(size: 10))
					.foregroundStyle(Palette.dim)
			}
		}
	}
}

struct ProgressBar: View {
	let fraction: Double
	let tint: Color

	var body: some View {
		GeometryReader { geo in
			ZStack(alignment: .leading) {
				RoundedRectangle(cornerRadius: 3)
					.fill(Palette.dim.opacity(0.18))
				RoundedRectangle(cornerRadius: 3)
					.fill(tint)
					.frame(width: geo.size.width * max(0, min(1, fraction)))
			}
		}
		.frame(height: 6)
	}
}

extension Date {
	/// "in 3d 14h", "in 47m", "1m ago".
	func relativeShort(reference: Date = Date()) -> String {
		let interval = self.timeIntervalSince(reference)
		let abs = Swift.abs(interval)
		let suffix: String
		let prefix: String
		if interval >= 0 {
			prefix = "in "
			suffix = ""
		} else {
			prefix = ""
			suffix = " ago"
		}

		if abs < 60 { return "\(prefix)< 1m\(suffix)" }
		if abs < 3600 {
			return "\(prefix)\(Int(abs / 60))m\(suffix)"
		}
		if abs < 86400 {
			let h = Int(abs / 3600)
			let m = Int((abs.truncatingRemainder(dividingBy: 3600)) / 60)
			return m > 0 ? "\(prefix)\(h)h \(m)m\(suffix)" : "\(prefix)\(h)h\(suffix)"
		}
		let d = Int(abs / 86400)
		let h = Int((abs.truncatingRemainder(dividingBy: 86400)) / 3600)
		return h > 0 ? "\(prefix)\(d)d \(h)h\(suffix)" : "\(prefix)\(d)d\(suffix)"
	}
}
