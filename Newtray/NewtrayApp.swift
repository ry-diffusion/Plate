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
        // A status bar é um NSStatusItem (ver StatusItemController); o app
        // não tem janela.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(monitor: HotspotMonitor())
    }
}
