//
//  NewtrayApp.swift
//  Newtray
//
//  Created by Moizes Sousa on 01/10/26.
//

import SwiftUI

@main
struct NewtrayApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        // The menu bar item is an NSStatusItem (see StatusItemController); the
        // app has no windows.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchAtLogin.enableOnFirstLaunch()
        statusItemController = StatusItemController(monitor: HotspotMonitor(), network: NetworkMonitor())
    }
}
