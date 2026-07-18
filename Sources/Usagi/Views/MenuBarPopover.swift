import SwiftUI

/// The header view at the top of the status-item menu: the usage bars when
/// signed in, or a short explanatory message / spinner otherwise. Its only
/// control is the ↻ refresh button, which updates the bars in place without
/// closing the menu. The actual actions (Settings, Sign in/out, Quit) are
/// native `NSMenuItem`s built by the app delegate, so they get the system
/// menu's instant, native behaviour.
struct MenuBarPopover: View {
	let appState: AppState

	var body: some View {
		Group {
			switch appState.phase {
			case .bootstrapping, .loading:
				ProgressView()
					.controlSize(.small)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 18)
			case .signedOut:
				message(
					title: "Not signed in",
					body: "Sign in to Claude.ai to track your session, weekly, and extra-usage limits.",
					bodyColor: Palette.dim
				)
			case .ready:
				ready
			case .error(let text):
				message(title: "Couldn't load usage", body: text, bodyColor: .red)
			}
		}
		.frame(width: 280)
	}

	@ViewBuilder
	private var ready: some View {
		VStack(alignment: .leading, spacing: 10) {
			if let snapshot = appState.snapshot {
				UsageBarsView(snapshot: snapshot, overage: appState.overage, showPercent: appState.showPercentInBars)
			}
			// Fixed-height slot so the header doesn't jump as the line swaps
			// between "Updating…" and "Updated Xs ago". The ↻ button refreshes
			// in place — clicks on a view-backed menu item don't dismiss the menu.
			HStack(spacing: 5) {
				Spacer()
				if appState.isRefreshing {
					ProgressView()
						.controlSize(.mini)
						.scaleEffect(0.6)
					Text("Updating…")
				} else if let last = appState.lastRefresh {
					Text("Updated \(last.relativeShort())")
				}
				Button {
					Task { await appState.refresh(userInitiated: true) }
				} label: {
					Image(systemName: "arrow.clockwise")
						.font(.system(size: 9, weight: .semibold))
				}
				.buttonStyle(.plain)
				.disabled(appState.isRefreshing)
				.help("Refresh now")
				.accessibilityLabel("Refresh usage now")
			}
			.font(.system(size: 10))
			.foregroundStyle(Palette.dim)
			.frame(maxWidth: .infinity, minHeight: 12)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
	}

	private func message(title: String, body: String, bodyColor: Color) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(title)
				.font(.system(size: 13, weight: .semibold))
			Text(body)
				.font(.system(size: 11))
				.foregroundStyle(bodyColor)
				.fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
	}
}
