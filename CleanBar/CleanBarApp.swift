//
//  CleanBarApp.swift
//  CleanBar
//
//  Created by Alain Lima on 25/08/2026.
//

import Cocoa
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    public static private(set) var shared: AppDelegate?

    public private(set) var stateStore: StateStore!
    public private(set) var observer: StatusBarObserver!
    public private(set) var layoutController: LayoutController!
    public private(set) var hoverMonitor: HoverMonitor!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSLog("🚀 CleanBar applicationDidFinishLaunching started!")

        let store = StateStore()
        let obs = StatusBarObserver(stateStore: store)
        let layout = LayoutController()
        let hover = HoverMonitor()

        self.stateStore = store
        self.observer = obs
        self.layoutController = layout
        self.hoverMonitor = hover

        // Explicitly setup status items in applicationDidFinishLaunching
        layout.spacerController.setupStatusItem()

        // Connect Floating Panel frame to HoverMonitor so hovering over the sub-bar keeps it open
        hover.floatingPanelFrameProvider = { [weak layout] in
            return layout?.spacerController.floatingShelf.panelFrame
        }

        // Configure spacer controller and item interaction callbacks
        layout.spacerController.configure(
            observer: obs,
            stateStore: store,
            onItemTriggered: { [weak hover] in
                hover?.isInteracting = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    hover?.isInteracting = false
                }
            }
        )

        // Connect hover detection
        hover.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.layoutController.applyVisibility(isHovered: isHovered, observer: self.observer)
        }

        obs.onItemsUpdated = { [weak self] in
            guard let self = self else { return }
            self.layoutController.spacerController.enforceHiding()
            self.layoutController.applyVisibility(isHovered: self.hoverMonitor.isCurrentlyHovered, observer: self.observer)
        }

        hover.startMonitoring()
        obs.scanMenuBarItems()
        layout.applyVisibility(isHovered: false, observer: obs)
        layout.spacerController.enforceHiding()

        NSLog("🚀 CleanBar status item setup completed!")

        if !store.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.layoutController.spacerController.openOnboarding()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SkyLightWindowManager.shared.showAllItems()
    }
}
