import SwiftUI

struct MenuBarPopover: View {
	let appState: AppState

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			content
		}
		.frame(width: 300)
	}

	@ViewBuilder
	private var content: some View {
		switch appState.phase {
		case .bootstrapping, .loading:
			loadingView
		case .signedOut:
			LoginView(appState: appState)
		case .ready:
			readyView
		case .error(let message):
			errorView(message: message)
		}
	}

	private var loadingView: some View {
		VStack {
			Spacer()
			ProgressView()
			Spacer()
		}
		.frame(minHeight: 120)
	}

	@ViewBuilder
	private var readyView: some View {
		VStack(alignment: .leading, spacing: 0) {
			if let snapshot = appState.snapshot {
				UsageBarsView(snapshot: snapshot, overage: appState.overage)
					.padding(.horizontal, 14)
					.padding(.top, 14)
			}

			divider
			footerRows

			if let last = appState.lastRefresh {
				Text("Updated \(last.relativeShort())")
					.font(.system(size: 10))
					.foregroundStyle(Palette.dim)
					.frame(maxWidth: .infinity, alignment: .trailing)
					.padding(.horizontal, 14)
					.padding(.top, 4)
					.padding(.bottom, 8)
			}
		}
	}

	private func errorView(message: String) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(message)
				.font(.system(size: 12))
				.foregroundStyle(.red)
				.padding(.horizontal, 14)
				.padding(.top, 14)
			MenuRow("Try again") {
				Task { await appState.refresh() }
			}
			.padding(.horizontal, 4)

			divider
			footerRows
				.padding(.bottom, 8)
		}
	}

	private var divider: some View {
		Divider()
			.padding(.horizontal, 6)
			.padding(.vertical, 8)
	}

	private var footerRows: some View {
		VStack(alignment: .leading, spacing: 0) {
			MenuRow("Settings…", shortcut: "⌘,") {
				NotificationCenter.default.post(name: .openSettings, object: nil)
			}
			.keyboardShortcut(",", modifiers: .command)

			MenuRow("Sign out") {
				appState.signOut()
			}

			MenuRow("Quit usagi", shortcut: "⌘Q") {
				NSApplication.shared.terminate(nil)
			}
			.keyboardShortcut("q", modifiers: .command)
		}
		.padding(.horizontal, 4)
	}
}
