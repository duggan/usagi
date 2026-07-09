import SwiftUI

enum Palette {
	static let weekly = Color.blue
	static let opus = Color.purple
	static let fable = Color.indigo
	static let sonnet = Color.green
	static let session = Color.teal
	static let overage = Color.orange
	static let dim = Color.secondary

	/// Tint for a scoped weekly cap, keyed off the API's `display_name`. Unknown
	/// scopes (a new model, or a surface breakout) fall back to a muted weekly
	/// blue so they still read as belonging to the weekly group.
	static func scope(_ displayName: String) -> Color {
		switch displayName.lowercased() {
		case "fable": fable
		case "opus": opus
		case "sonnet": sonnet
		default: weekly.opacity(0.55)
		}
	}
}
