import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("NTFSMate: applicationDidFinishLaunching — process is alive")
        do {
            try NTFSManager.shared.registerHelperIfNeeded()
        } catch {
            NSLog("NTFSHelper registration failed: \(error.localizedDescription)")
        }
        menuBarController = MenuBarController()
        NSLog("NTFSMate: menu bar controller created, status item should be visible now")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

NSLog("NTFSMate: main.swift entry point reached")
let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
