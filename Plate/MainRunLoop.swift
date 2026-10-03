//
//  MainRunLoop.swift
//  Plate
//
//  Delivers work to the main thread in the run loop's common modes. While a
//  menu is open, the main run loop runs in event-tracking mode and doesn't get
//  to DispatchQueue.main work until the menu closes, so scan results, signal
//  changes and the iPhone's updates would freeze in an open menu.
//

import Foundation

nonisolated func onMainRunLoop(_ work: @escaping @MainActor () -> Void) {
    let mainLoop = CFRunLoopGetMain()
    CFRunLoopPerformBlock(mainLoop, CFRunLoopMode.commonModes.rawValue) {
        MainActor.assumeIsolated { work() }
    }
    CFRunLoopWakeUp(mainLoop)
}
