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

        // Keep visibility synced when status items change
        obs.onItemsUpdated = { [weak obs] in
            guard let obs = obs else { return }
            layout.applyVisibility(isHovered: hover.isCurrentlyHovered, observer: obs)
        }

        hover.startMonitoring()
        obs.scanMenuBarItems()

        // 1. Start initially expanded (24px) so status item window is positioned accurately by WindowServer
        layout.spacerController.setExpanded(true)

        // 2. Smoothly collapse after 0.4s once WindowServer placement is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak obs] in
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
