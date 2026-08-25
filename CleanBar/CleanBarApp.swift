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
    public var stateStore: StateStore?
    public var observer: StatusBarObserver?
    public var layoutController: LayoutController?
    public var hoverMonitor: HoverMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let store = StateStore()
        let obs = StatusBarObserver(stateStore: store)
        let layout = LayoutController()
        let hover = HoverMonitor()

        self.stateStore = store
        self.observer = obs
        self.layoutController = layout
        self.hoverMonitor = hover

        // Explicitly setup status item in applicationDidFinishLaunching
        layout.spacerController.setupStatusItem()
        layout.spacerController.configure(observer: obs, stateStore: store)

        // Connect hover detection
        hover.onHoverChanged = { [weak self] isHovered in
            guard let self = self, let observer = self.observer else { return }
            self.layoutController?.applyVisibility(isHovered: isHovered, observer: observer)
        }

        obs.onItemsUpdated = { [weak self] in
            guard let self = self, let observer = self.observer, let hover = self.hoverMonitor else { return }
            self.layoutController?.applyVisibility(isHovered: hover.isCurrentlyHovered, observer: observer)
        }

        hover.startMonitoring()
        obs.scanMenuBarItems()
        layout.applyVisibility(isHovered: false, observer: obs)

        if !store.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.layoutController?.spacerController.openOnboarding()
            }
        }
    }
}

@main
struct CleanBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            if let obs = appDelegate.observer, let store = appDelegate.stateStore {
                SettingsView(observer: obs, stateStore: store)
            } else {
                EmptyView()
            }
        }
    }
}
