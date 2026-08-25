import XCTest
@testable import CleanBar

final class StateStoreTests: XCTestCase {
    private var testUserDefaults: UserDefaults!
    private let suiteName = "com.barbar.tests.statestore"

    override func setUp() {
        super.setUp()
        testUserDefaults = UserDefaults(suiteName: suiteName)!
        testUserDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        testUserDefaults.removePersistentDomain(forName: suiteName)
        testUserDefaults = nil
        super.tearDown()
    }

    func testItemCategoryRawValues() {
        XCTAssertEqual(ItemCategory.hiddenOnHover.rawValue, "hiddenOnHover")
        XCTAssertEqual(ItemCategory.deepHidden.rawValue, "deepHidden")
    }

    func testItemConfigInit() {
        let configDefault = ItemConfig(id: "app.test", category: .hiddenOnHover)
        XCTAssertEqual(configDefault.id, "app.test")
        XCTAssertEqual(configDefault.category, .hiddenOnHover)
        XCTAssertEqual(configDefault.orderIndex, 0)

        let configCustom = ItemConfig(id: "app.custom", category: .deepHidden, orderIndex: 5)
        XCTAssertEqual(configCustom.id, "app.custom")
        XCTAssertEqual(configCustom.category, .deepHidden)
        XCTAssertEqual(configCustom.orderIndex, 5)
    }

    func testDefaultCategoryIsHiddenOnHover() {
        let store = StateStore(userDefaults: testUserDefaults)
        XCTAssertEqual(store.category(for: "com.unknown.app"), .hiddenOnHover)
    }

    func testSetAndRetrieveCategory() {
        let store = StateStore(userDefaults: testUserDefaults)
        store.setCategory(.deepHidden, for: "com.apple.wifi")
        XCTAssertEqual(store.category(for: "com.apple.wifi"), .deepHidden)

        store.setCategory(.deepHidden, for: "com.apple.bluetooth")
        XCTAssertEqual(store.category(for: "com.apple.bluetooth"), .deepHidden)
    }

    func testOverwriteExistingCategory() {
        let store = StateStore(userDefaults: testUserDefaults)
        store.setCategory(.hiddenOnHover, for: "com.test.app")
        XCTAssertEqual(store.category(for: "com.test.app"), .hiddenOnHover)

        store.setCategory(.deepHidden, for: "com.test.app")
        XCTAssertEqual(store.category(for: "com.test.app"), .deepHidden)
    }

    func testMultipleItemsPreserved() {
        let store = StateStore(userDefaults: testUserDefaults)
        store.setCategory(.hiddenOnHover, for: "com.item1")
        store.setCategory(.deepHidden, for: "com.item2")

        XCTAssertEqual(store.category(for: "com.item1"), .hiddenOnHover)
        XCTAssertEqual(store.category(for: "com.item2"), .deepHidden)
    }

    func testPersistenceAcrossInstances() {
        let store1 = StateStore(userDefaults: testUserDefaults)
        store1.setCategory(.deepHidden, for: "com.apple.controlcenter")

        let store2 = StateStore(userDefaults: testUserDefaults)
        XCTAssertEqual(store2.category(for: "com.apple.controlcenter"), .deepHidden)
    }

    func testCorruptedDataFallback() {
        testUserDefaults.set("corrupted-string-data".data(using: .utf8), forKey: "CleanBarItemConfigs")
        let store = StateStore(userDefaults: testUserDefaults)
        XCTAssertEqual(store.category(for: "com.any.app"), .hiddenOnHover)
    }
}
