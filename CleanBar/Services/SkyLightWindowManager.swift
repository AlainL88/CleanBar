import Cocoa
import CoreGraphics

public typealias CGSConnectionID = UInt32
public typealias CGSWindowID = UInt32

/// Manages direct WindowServer visibility of third-party status bar items via SkyLight private framework.
@MainActor
public final class SkyLightWindowManager {
    public static let shared = SkyLightWindowManager()

    private typealias CGSMainConnectionIDFunc = @convention(c) () -> CGSConnectionID
    private typealias SLSSetWindowAlphaFunc = @convention(c) (CGSConnectionID, CGSWindowID, Float) -> Int32

    private var connectionID: CGSConnectionID = 0
    private var setWindowAlphaFunc: SLSSetWindowAlphaFunc?
    private var hiddenWindowIDs: Set<CGSWindowID> = []

    public init() {
        setupSkyLight()
    }

    private func setupSkyLight() {
        guard let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW) else {
            return
        }

        if let mainConnSymbol = dlsym(skyLight, "CGSMainConnectionID"),
           let setAlphaSymbol = dlsym(skyLight, "SLSSetWindowAlpha") ?? dlsym(skyLight, "CGSSetWindowAlpha") {
            let getConn = unsafeBitCast(mainConnSymbol, to: CGSMainConnectionIDFunc.self)
            self.connectionID = getConn()
            self.setWindowAlphaFunc = unsafeBitCast(setAlphaSymbol, to: SLSSetWindowAlphaFunc.self)
        }
    }

    /// Hides all status bar item windows located to the left of CleanBar's Eye icon.
    public func hideItemsToTheLeft(of eyeX: CGFloat) {
        guard let setAlpha = setWindowAlphaFunc, connectionID != 0 else { return }

        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let selfPID = ProcessInfo.processInfo.processIdentifier

        for win in windowList {
            let layer = win[kCGWindowLayer as String] as? Int ?? 0
            let boundsDict = win[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) ?? .zero
            let ownerPID = win[kCGWindowOwnerPID as String] as? Int32 ?? 0
            let winID = CGSWindowID(win[kCGWindowNumber as String] as? Int ?? 0)

            // Status bar layer is 25 (kCGStatusWindowLevel)
            guard layer == 25, bounds.origin.y <= 40, bounds.origin.y >= 0, bounds.height <= 40, bounds.width > 0, bounds.width < 500 else {
                continue
            }

            guard ownerPID != selfPID else { continue }

            // Target items strictly to the left of CleanBar's Eye icon
            if bounds.maxX < eyeX {
                _ = setAlpha(connectionID, winID, 0.0)
                hiddenWindowIDs.insert(winID)
            }
        }
    }

    /// Restores full visibility of all previously hidden status bar windows.
    public func showAllItems() {
        guard let setAlpha = setWindowAlphaFunc, connectionID != 0 else { return }

        for winID in hiddenWindowIDs {
            _ = setAlpha(connectionID, winID, 1.0)
        }
        hiddenWindowIDs.removeAll()
    }
}
