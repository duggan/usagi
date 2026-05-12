import AppKit

/// How full the session-usage gauge is — drives the battery bar's colour, which
/// ramps green → yellow → orange → red as the quota fills.
enum GaugeLevel: Equatable {
	case nominal, elevated, high, critical

	/// `fraction` is 0…1 of the session quota used.
	static func forUsage(_ fraction: Double) -> GaugeLevel {
		switch fraction {
		case ..<0.5:  return .nominal
		case ..<0.75: return .elevated
		case ..<0.9:  return .high
		default:      return .critical
		}
	}

	var color: NSColor {
		switch self {
		case .nominal:  return .systemGreen
		case .elevated: return .systemYellow
		case .high:     return .systemOrange
		case .critical: return .systemRed
		}
	}
}

/// How close the rolling 5-hour session window is to resetting — drives the
/// countdown dial's colour, warming yellow then orange in the final minutes.
enum DialUrgency: Equatable {
	case calm, soon, imminent

	/// `remaining` is 0…1 of the window left, or `nil` when there's no active window.
	static func forRemaining(_ remaining: Double?) -> DialUrgency {
		guard let f = remaining else { return .calm }
		switch f {
		case ..<0.033: return .imminent   // ≲ 10 min left
		case ..<0.10:  return .soon       // ≲ 30 min left
		default:       return .calm
		}
	}

	var color: NSColor {
		switch self {
		case .calm:     return .labelColor
		case .soon:     return .systemYellow
		case .imminent: return .systemOrange
		}
	}
}
