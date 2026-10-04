import DiskArbitration
import Foundation

protocol USBMonitorDelegate: AnyObject {
    func usbMonitor(_ monitor: USBMonitor, driveAppeared drive: DriveInfo)
    func usbMonitor(_ monitor: USBMonitor, driveDisappeared bsdName: String)
}

/// Watches for USB disk arrival/removal via DiskArbitration. This is push-based
/// (no polling of /Volumes), so a freshly inserted drive is reported within the
/// same runloop tick DiskArbitration learns about it from the kernel.
final class USBMonitor {
    weak var delegate: USBMonitorDelegate?

    private var session: DASession?

    func start() {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            assertionFailure("Failed to create DASession")
            return
        }
        self.session = session
        DASessionSetDispatchQueue(session, DispatchQueue.main)

        // Match only USB-attached media; internal/network volumes never reach these callbacks.
        let match = [kDADiskDescriptionDeviceProtocolKey: "USB"] as CFDictionary
        let context = Unmanaged.passUnretained(self).toOpaque()

        DARegisterDiskAppearedCallback(session, match, { disk, context in
            guard let context else { return }
            let monitor = Unmanaged<USBMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handleAppeared(disk)
        }, context)

        DARegisterDiskDisappearedCallback(session, match, { disk, context in
            guard let context else { return }
            let monitor = Unmanaged<USBMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handleDisappeared(disk)
        }, context)
    }

    func stop() {
        guard let session else { return }
        DASessionSetDispatchQueue(session, nil)
        self.session = nil
    }

    private func handleAppeared(_ disk: DADisk) {
        guard let bsdName = DADiskGetBSDName(disk).map({ String(cString: $0) }) else { return }
        guard let description = DADiskCopyDescription(disk) as NSDictionary? else { return }

        // Skip the whole-disk object when a volume-level object for the same media
        // will also fire; whole-disk appearances matter only for still-unformatted
        // media (no child volume will ever appear for those).
        let isWhole = (description[kDADiskDescriptionMediaWholeKey as String] as? Bool) ?? false
        let volumeKind = description[kDADiskDescriptionVolumeKindKey as String] as? String
        if isWhole && volumeKind != nil { return }

        let volumeName = description[kDADiskDescriptionVolumeNameKey as String] as? String ?? bsdName
        let sizeBytes = (description[kDADiskDescriptionMediaSizeKey as String] as? NSNumber)?.uint64Value ?? 0
        let isRemovable = (description[kDADiskDescriptionMediaRemovableKey as String] as? Bool) ?? true

        let fileSystem: DriveInfo.FileSystem
        if let kind = volumeKind {
            fileSystem = kind.lowercased().contains("ntfs") ? .ntfs : .other(kind)
        } else {
            fileSystem = .unformatted
        }

        let drive = DriveInfo(
            bsdName: bsdName,
            volumeName: volumeName,
            fileSystem: fileSystem,
            sizeBytes: sizeBytes,
            isRemovable: isRemovable
        )
        delegate?.usbMonitor(self, driveAppeared: drive)
    }

    private func handleDisappeared(_ disk: DADisk) {
        guard let bsdName = DADiskGetBSDName(disk).map({ String(cString: $0) }) else { return }
        delegate?.usbMonitor(self, driveDisappeared: bsdName)
    }
}
