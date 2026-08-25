//
//  CleanBarApp.swift
//  CleanBar
//
//  Created by Alain Lima on 25/08/2026.
//

import SwiftUI
import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    public let stateStore = StateStore()
    public let observer: StatusBarObserver
    public let layoutController = LayoutController()
    public let hoverMonitor = HoverMonitor()

    override init() {
        let store = StateStore()
        let obs = StatusBarObserver(stateStore: store)
        self.observer = obs
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        // Configure status items and floating shelf
        layoutController.spacerController.configure(observer: observer, stateStore: stateStore)

        // Connect hover detection
        hoverMonitor.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.layoutController.applyVisibility(isHovered: isHovered, observer: self.observer)
        }

        observer.onItemsUpdated = { [weak self] in
            guard let self = self else { return }
            self.layoutController.applyVisibility(isHovered: self.hoverMonitor.isCurrentlyHovered, observer: self.observer)
        }

        hoverMonitor.startMonitoring()
        observer.scanMenuBarItems()
        layoutController.applyVisibility(isHovered: false, observer: observer)

        if !stateStore.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.layoutController.spacerController.openOnboarding()
            }
        }
    }
}

@main
struct CleanBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(observer: appDelegate.observer, stateStore: appDelegate.stateStore)
        }
    }
}
