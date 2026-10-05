import AppKit
import SwiftUI

/// The app runs as a pure menu-bar accessory (no Dock icon, no app switcher
/// entry) until this window opens — same pattern Paragon's own app uses:
/// a quick menu-bar helper plus a full window you open on demand. Switching
/// to .regular while the window is open gives it a proper Dock icon and
/// Cmd+Tab entry; closing it reverts to accessory so the menu bar icon is
/// the only persistent presence again.
final class MainWindowController: NSWindowController, NSWindowDelegate {
    convenience init(model: DriveListModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NTFSMate"
        window.contentViewController = NSHostingController(rootView: MainWindowView(model: model))
        window.center()
        self.init(window: window)
        window.delegate = self
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
