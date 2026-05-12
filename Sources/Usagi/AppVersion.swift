import Foundation

enum AppVersion {
	static var short: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
	}

	static var build: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
	}
}
