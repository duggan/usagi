import SwiftUI
import ServiceManagement

struct SettingsView: View {
	@Bindable var appState: AppState
	@State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

	var body: some View {
		Form {
			Section {
				Picker("Interval", selection: $appState.refreshInterval) {
					Text("5s").tag(TimeInterval(5))
					Text("30s").tag(TimeInterval(30))
					Text("5m").tag(TimeInterval(300))
				}
				.pickerStyle(.segmented)
			} header: {
				Text("Refresh")
			} footer: {
				Text("How often usage data is fetched from Claude.ai.")
			}

			Section("Display") {
				Toggle("Show percentage in usage bars", isOn: $appState.showPercentInBars)
			}

			Section("Startup") {
				Toggle("Launch at login", isOn: $launchAtLogin)
					.onChange(of: launchAtLogin) { _, new in setLaunchAtLogin(new) }
			}

			Section("Account") {
				if let org = appState.organization {
					LabeledContent("Signed in as", value: org.name)
					Button("Sign Out") { appState.signOut() }
				} else {
					LabeledContent("Status", value: "Not signed in")
					Button("Sign In…") { appState.presentSignIn() }
				}
			}

			Section("About") {
				LabeledContent("Version", value: AppVersion.short)
				Link("github.com/rossduggan/usagi",
				     destination: URL(string: "https://github.com/rossduggan/usagi")!)
			}
		}
		.formStyle(.grouped)
		.scrollDisabled(true)
		.frame(width: 460, height: 620)
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
