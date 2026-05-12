import Foundation

struct Organization: Codable, Identifiable, Hashable {
	let uuid: String
	let name: String

	var id: String { uuid }
}
