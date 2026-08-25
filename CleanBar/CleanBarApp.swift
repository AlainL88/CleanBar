//
//  CleanBarApp.swift
//  CleanBar
//
//  Created by Alain Lima on 25/08/2026.
//

import SwiftUI

@main
struct CleanBarApp: App {
    @StateObject private var observer: StatusBarObserver
    private let stateStore: StateStore
    private let hoverMonitor: HoverMonitor
    private let layoutController: LayoutController

    init() {
        // Set activation policy to accessory (menu bar app without dock icon)
        NSApplication.shared.setActivationPolicy(.accessory)
        let store = StateStore()
        let obs = StatusBarObserver(stateStore: store)
        let layout = LayoutController()
        let hover = HoverMonitor()

        self._observer = StateObject(wrappedValue: obs)
        self.stateStore = store
        self.hoverMonitor = hover
        self.layoutController = layout

        // Configure single unified status item
        layout.spacerController.configure(observer: obs, stateStore: store)

        // Connect hover detection to visibility controller
        hover.onHoverChanged = { [weak obs] isHovered in
            guard let obs = obs else { return }
            layout.applyVisibility(isHovered: isHovered, observer: obs)
        }

        // Automatically enforce collapsed visibility on startup when items are scanned
        obs.onItemsUpdated = { [weak obs] in
            guard let obs = obs else { return }
            layout.applyVisibility(isHovered: hover.isCurrentlyHovered, observer: obs)
        }

        hover.startMonitoring()
        obs.scanMenuBarItems()

        // Allow WindowServer 0.2s to lay out the status item window on screen before initial collapse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak obs] in
            guard let obs = obs else { return }
            layout.applyVisibility(isHovered: false, observer: obs)
        }

        // Launch onboarding automatically on first launch
        if !store.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                layout.spacerController.openOnboarding()
            }
        }
    }

    var body: some Scene {
        Settings {
            SettingsView(observer: observer, stateStore: stateStore)
        }
    }
}
