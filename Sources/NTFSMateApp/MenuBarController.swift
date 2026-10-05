import AppKit
import SwiftUI

final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model = DriveListModel()
    private let usbMonitor = USBMonitor()
    private var mainWindowController: MainWindowController?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "externaldrive.connected.to.line.below", accessibilityDescription: "NTFSMate")
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: DriveListView(model: model, onOpenMainWindow: { [weak self] in self?.openMainWindow() })
        )

        usbMonitor.delegate = model
        usbMonitor.start()
        model.refreshDiagnostics()
    }

    private func openMainWindow() {
        popover.performClose(nil)
        if mainWindowController == nil {
            mainWindowController = MainWindowController(model: model)
        }
        mainWindowController?.show()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refreshDiagnostics()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
