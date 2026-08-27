import Cocoa
import ScreenCaptureKit

/// Controller managing the overlay that hides the menu bar items to the left of
/// CleanBar's Eye icon.
///
/// On recent macOS (26+) the private SkyLight window APIs no longer hide menu bar
/// item windows (they return success but the Window Server ignores them), so the
/// only reliable way to hide the items is an opaque surface ABOVE them. To make
/// that surface indistinguishable from the menu bar, it is painted with a captured
/// strip of the bar itself (the frosted wallpaper WITHOUT the items), stretched
/// across the hidden span. Mouse events pass through, so the hidden items remain
/// clickable from the floating shelf.
@MainActor
public final class MenuBarCurtainController: NSObject {
    public static let shared = MenuBarCurtainController()

    private var curtainWindow: NSWindow?
    private var backgroundImageView: NSImageView?
    private var lastCaptureX: CGFloat = -1
    private var lastCaptureTime: TimeInterval = 0
    public private(set) var isCurtainActive: Bool = false

    public override init() {
        super.init()
    }

    /// Captures a wide clean strip of the menu bar (wallpaper-blur, no items) just
    /// left of the curtain and stretches it across the hidden span, so the hidden
    /// area blends with the surrounding bar. Runs off-main; throttled.
    private func captureMenuBarBackground(startX: CGFloat, endX: CGFloat, menuBarTop: CGFloat, menuBarHeight: CGFloat) async {
        let now = ProcessInfo.processInfo.systemUptime
        guard abs(startX - lastCaptureX) > 20 || (now - lastCaptureTime) > 2.0 else { return }
        lastCaptureX = startX
        lastCaptureTime = now

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: startX, y: menuBarTop - 1)) })
                ?? content.displays.first else { return }

            let scale = CGFloat(display.width) / display.frame.width
            // Capture a strip the SAME width as the curtain, immediately left of it, so
            // it can be shown at natural size without stretching (which washed out the
            // frosted texture). Its right edge aligns with the curtain's left edge.
            let spanWidthPts = max(24, endX - startX)
            let left = max(0, startX - spanWidthPts)

            let config = SCStreamConfiguration()
            config.width = Int(spanWidthPts * scale)
            config.height = Int(menuBarHeight * scale)
            config.showsCursor = false
            // Display coordinates are top-left origin, in points.
            config.sourceRect = CGRect(x: left, y: display.frame.height - menuBarTop, width: spanWidthPts, height: menuBarHeight)

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            // Calibrate: ScreenCaptureKit renders the bar slightly brighter than the
            // real screen, so darken the strip a touch to match the surrounding bar.
            let calibrated = Self.darkened(image, amount: 0.04) ?? image
            let strip = NSImage(cgImage: calibrated, size: NSSize(width: spanWidthPts, height: menuBarHeight))
            self.backgroundImageView?.image = strip
            NSLog("🪟 curtain: background captured \(image.width)x\(image.height)")
        } catch {
            NSLog("🪟 curtain: background capture failed: \(error)")
        }
    }

    /// Updates or activates the curtain to cover only the span of the hidden items
    /// located strictly to the left of CleanBar's Eye icon. The Apple menu and app
    /// menu titles are never covered.
    public func updateCurtain(eyeX: CGFloat, menuBarTop: CGFloat, menuBarHeight: CGFloat, hiddenFrames: [CGRect] = []) {
        // Only on-screen items can be covered: another menu bar tool (e.g. Ice) may
        // push items to negative X, which would otherwise make the span invalid.
        let onScreenFrames = hiddenFrames.filter { $0.minX >= 0 && $0.width > 0 }
        let startX = (onScreenFrames.map(\.minX).min() ?? eyeX) - 4.0
        let width = eyeX - startX
        guard startX > 0, width > 24, menuBarTop > 0, menuBarHeight >= 24 else {
            hideCurtain()
            return
        }

        let h = menuBarHeight
        let curtainFrame = NSRect(x: startX, y: menuBarTop - h, width: width, height: h)
        NSLog("🪟 curtain: startX=%.1f eyeX=%.1f menuBarTop=%.1f h=%.1f frame=%@ hiddenFrames=%@",
              startX, eyeX, menuBarTop, h,
              NSStringFromRect(curtainFrame), hiddenFrames.map { NSStringFromRect($0) }.joined(separator: ","))

        if curtainWindow == nil {
            let win = NSWindow(
                contentRect: curtainFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
            win.isOpaque = false
            win.backgroundColor = fallbackColor()
            win.hasShadow = false
            win.hidesOnDeactivate = false
            win.ignoresMouseEvents = true

            // The curtain shows the captured strip (the wallpaper gradient with the
            // bar's own frosted texture). It is shown at natural size — stretching
            // would wash out the texture.
            let imageView = NSImageView(frame: win.contentView?.bounds ?? .zero)
            imageView.autoresizingMask = [.width, .height]
            imageView.imageScaling = .scaleNone
            imageView.wantsLayer = true
            win.contentView = imageView
            self.backgroundImageView = imageView
            self.curtainWindow = win
        }

        curtainWindow?.setFrame(curtainFrame, display: true)
        curtainWindow?.orderFrontRegardless()
        isCurtainActive = true

        Task { [weak self] in
            await self?.captureMenuBarBackground(startX: startX, endX: startX + width, menuBarTop: menuBarTop, menuBarHeight: menuBarHeight)
        }
    }

    /// Hides the curtain overlay.
    public func hideCurtain() {
        curtainWindow?.orderOut(nil)
        isCurtainActive = false
    }

    /// Darkens an image by drawing a black overlay at the given opacity — used to
    /// calibrate the captured menu bar strip to the screen's actual appearance.
    nonisolated private static func darkened(_ image: CGImage, amount: CGFloat) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let ctx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(NSColor.black.withAlphaComponent(amount).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// Initial solid color used until the first background capture arrives.
    private func fallbackColor() -> NSColor {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedWhite: 0.15, alpha: 1.0)
            : NSColor(calibratedWhite: 0.95, alpha: 1.0)
    }
}
