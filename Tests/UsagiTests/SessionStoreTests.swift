import XCTest
@testable import Usagi

/// Round-trips the Keychain CRUD using a per-test service name so we never
/// touch the user's real `ie.duggan.usagi.session` entry.
final class SessionStoreTests: XCTestCase {

	private var store: SessionStore!

	override func setUp() {
		super.setUp()
		store = SessionStore(service: "ie.duggan.usagi.test.\(UUID().uuidString)",
		                     account: "test")
	}

	override func tearDown() {
		store.delete()
		store = nil
		super.tearDown()
	}

	func testWriteThenRead() throws {
		try store.write("sk-ant-1234")
		XCTAssertEqual(store.read(), "sk-ant-1234")
	}

	func testReadMissingReturnsNil() {
		XCTAssertNil(store.read())
	}

	func testWriteOverwritesExisting() throws {
		try store.write("sk-ant-first")
		try store.write("sk-ant-second")
		XCTAssertEqual(store.read(), "sk-ant-second")
	}

	func testDeleteExistingReturnsTrue() throws {
		try store.write("sk-ant-1234")
		XCTAssertTrue(store.delete())
		XCTAssertNil(store.read())
	}

	func testDeleteMissingReturnsTrue() {
		// Missing item is treated as "delete succeeded" so sign-out is idempotent.
		XCTAssertTrue(store.delete())
	}

	func testInstancesAreIsolatedByService() throws {
		let other = SessionStore(service: "ie.duggan.usagi.test.\(UUID().uuidString)",
		                         account: "test")
		defer { other.delete() }
		try store.write("sk-ant-self")
		try other.write("sk-ant-other")
		XCTAssertEqual(store.read(), "sk-ant-self")
		XCTAssertEqual(other.read(), "sk-ant-other")
	}
}
