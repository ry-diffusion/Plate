//
//  LaunchAtLogin.swift
//  Newtray
//
//  Opens Newtray at login through SMAppService (it shows up under System
//  Settings › General › Login Items).
//

import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Newtray: couldn't \(enabled ? "register" : "unregister") the login item: \(error)")
        }
    }

    /// Turns it on the first time the app runs. After that the user's choice
    /// from the menu sticks, even if they turned it off.
    static func enableOnFirstLaunch() {
        let key = "didSetUpLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        setEnabled(true)
    }
}
