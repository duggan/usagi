// swift-tools-version: 5.9
import PackageDescription

let package = Package(
	name: "Usagi",
	platforms: [.macOS(.v14)],
	targets: [
		.executableTarget(
			name: "Usagi",
			path: "Sources/Usagi",
			exclude: ["Info.plist"]
		),
	]
)
