//
//  CleanBarApp.swift
//  CleanBar
//
//  Created by Alain Lima on 25/08/2026.
//

import Cocoa
import SwiftUI
import ScreenCaptureKit

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

        // Single instance: if another CleanBar is already running, activate it and
        // quit this one (two instances would fight over the menu bar spacer/eye).
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            NSLog("🚀 Altro CleanBar attivo (pid \(existing.processIdentifier)) — termino questa istanza")
            existing.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
            return
        }

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

        // Connect the Eye icon frame to HoverMonitor so hover is scoped to the
        // CleanBar trigger area only (never the whole menu bar).
        hover.triggerFrameProvider = { [weak layout] in
            guard let button = layout?.spacerController.controlItem?.button,
                  let window = button.window else { return nil }
            return window.convertToScreen(button.frame)
        }

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

        // After a click toggles the shelf, coordinate with hover: opening engages
        // hover, closing suppresses it so the still-hovering cursor can't reopen it.
        layout.spacerController.onToggle = { [weak hover] expanded in
            guard let hover else { return }
            if expanded {
                hover.engageHover()
            } else {
                hover.suppressHoverUntilLeave()
            }
        }

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

        // Screen Recording is required to capture the items' real menu bar glyphs.
        // Trigger the system permission request immediately so the user can grant it
        // before the initial icon-capture scan runs.
        if !CGPreflightScreenCaptureAccess() {
            NSLog("🚀 Screen Recording non concessa — richiedo il permesso")
            SCShareableContent.getWithCompletionHandler { _, error in
                NSLog("🚀 Screen Recording request completata: \(String(describing: error))")
            }
        } else {
            NSLog("🚀 Screen Recording già concessa")
        }

        // Initial scan: wait for the Eye to settle, capture the hidden items'
        // faithful glyphs while they're still on-screen, then hide them via the
        // spacer. (setupStatusItem's first scheduled hide starts at 1.6s.)
        // Initial icon capture: keep the items visible (enforceHiding is suppressed
        // until ~4.5s) so this scan can capture their real on-screen glyphs via the
        // whole-display capture. If the items' persisted positions are negative they
        // are already off-screen and the capture simply yields the app-icon fallback.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self else { return }
            let eyeX = self.layoutController.spacerController.eyeScreenFrame()?.minX ?? 0
            self.observer.scanLeftHiddenItems(cleanBarEyeX: eyeX)
            self.layoutController.spacerController.enforceHiding()
        }

        NSLog("🚀 CleanBar status item setup completed!")

        if !store.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.layoutController.spacerController.openOnboarding()
            }
        }
    }

}
