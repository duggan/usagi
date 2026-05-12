import SwiftUI

struct LoginView: View {
	let appState: AppState

	var body: some View {
		VStack(spacing: 16) {
			Spacer()
			Text("usagi")
				.font(.system(size: 24, weight: .semibold))
			Text("Sign in to Claude.ai to track your weekly usage and overage spend.")
				.font(.system(size: 12))
				.foregroundStyle(Palette.dim)
				.multilineTextAlignment(.center)
				.padding(.horizontal)

			Button {
				appState.presentSignIn()
			} label: {
				Text("Sign in to Claude")
					.frame(maxWidth: .infinity)
			}
			.controlSize(.large)
			.buttonStyle(.borderedProminent)
			.padding(.horizontal)

			Spacer()

			Text("Your session token stays in the macOS Keychain.")
				.font(.system(size: 10))
				.foregroundStyle(Palette.dim)
				.padding(.bottom, 8)
		}
		.padding()
	}
}
