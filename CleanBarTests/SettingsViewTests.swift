import XCTest
import SwiftUI
@testable import CleanBar

@MainActor
final class SettingsViewTests: XCTestCase {
    private var testUserDefaults: UserDefaults!
    private var testSuiteName = "CleanBarSettingsViewTests"

    override func setUp() {
        super.setUp()
        testUserDefaults = UserDefaults(suiteName: testSuiteName)
        testUserDefaults?.removePersistentDomain(forName: testSuiteName)
    }

    override func tearDown() {
        testUserDefaults?.removePersistentDomain(forName: testSuiteName)
        testUserDefaults = nil
        super.tearDown()
    }

    func testInitialization() {
        let store = StateStore(userDefaults: testUserDefaults)
        let observer = StatusBarObserver(stateStore: store, scanner: { ["item1", "item2"] })
        let view = SettingsView(observer: observer, stateStore: store)

        XCTAssertNotNil(view.observer)
        XCTAssertNotNil(view.stateStore)
    }

    func testBodyViewHierarchyEvaluation() {
        let store = StateStore(userDefaults: testUserDefaults)
        let observer = StatusBarObserver(stateStore: store, scanner: {
            ["com.apple.wifi", "com.apple.volume"]
        })
        observer.scanMenuBarItems()

        let view = SettingsView(observer: observer, stateStore: store)
        let body = view.body

        XCTAssertNotNil(body)
    }
}
