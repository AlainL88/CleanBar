import Foundation
import Combine
import ServiceManagement

/// Manages macOS Launch at Login status using SMAppService (macOS 13+) with Applications folder validation.
public final class LaunchAtLoginService: ObservableObject {
    @Published public var isEnabled: Bool = false
    @Published public var statusMessage: String?
    @Published public var showInstallationAlert: Bool = false

    public var isInstalledInApplicationsFolder: Bool {
        let bundlePath = Bundle.main.bundlePath
        return bundlePath.hasPrefix("/Applications") || bundlePath.hasPrefix("/Users/\(NSUserName())/Applications")
    }

    public init() {
        checkStatus()
    }

    public func checkStatus() {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            self.isEnabled = (status == .enabled) && isInstalledInApplicationsFolder
            if !isInstalledInApplicationsFolder {
                self.statusMessage = "Please move CleanBar to /Applications folder to enable Launch at Login."
            } else {
                self.statusMessage = nil
            }
        } else {
            self.isEnabled = UserDefaults.standard.bool(forKey: "CleanBarLaunchAtLogin")
        }
    }

    public func setEnabled(_ enabled: Bool) {
        if enabled && !isInstalledInApplicationsFolder {
            self.isEnabled = false
            self.showInstallationAlert = true
            self.statusMessage = "Please move CleanBar to /Applications folder first."
            return
        }

        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                self.isEnabled = enabled
                self.statusMessage = nil
            } catch {
                print("LaunchAtLogin error: \(error)")
                self.isEnabled = false
                self.statusMessage = "Failed to update Login Items settings."
            }
        } else {
            UserDefaults.standard.set(enabled, forKey: "CleanBarLaunchAtLogin")
            self.isEnabled = enabled
        }
    }
}
