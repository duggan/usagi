import SwiftUI
import ServiceManagement

struct SettingsView: View {
	let appState: AppState
	@State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

	var body: some View {
		Form {
			Section("Refresh") {
				HStack {
					Slider(value: Binding(
						get: { appState.refreshInterval },
						set: { appState.refreshInterval = $0 }
					), in: 15...300, step: 5)
					Text("\(Int(appState.refreshInterval))s")
						.font(.system(size: 12).monospacedDigit())
						.frame(width: 44, alignment: .trailing)
				}
			}

			Section("Startup") {
				Toggle("Launch at login", isOn: $launchAtLogin)
					.onChange(of: launchAtLogin) { _, new in
						setLaunchAtLogin(new)
					}
			}

			Section("Account") {
				Button("Sign out") { appState.signOut() }
				if let org = appState.organization {
					Text("Signed in as \(org.name)")
						.font(.system(size: 11))
						.foregroundStyle(Palette.dim)
				}
			}

			Section("About") {
				HStack {
					Text("Version")
					Spacer()
					Text(AppVersion.short)
						.foregroundStyle(Palette.dim)
				}
				Link("github.com/rossduggan/usagi",
				     destination: URL(string: "https://github.com/rossduggan/usagi")!)
					.font(.system(size: 11))
			}
		}
		.formStyle(.grouped)
		.frame(width: 440, height: 420)
	}

	private func setLaunchAtLogin(_ enabled: Bool) {
		do {
			if enabled {
				try SMAppService.mainApp.register()
			} else {
				try SMAppService.mainApp.unregister()
			}
		} catch {
			NSLog("usagi: failed to set launch-at-login: \(error)")
			launchAtLogin = SMAppService.mainApp.status == .enabled
		}
	}
}
