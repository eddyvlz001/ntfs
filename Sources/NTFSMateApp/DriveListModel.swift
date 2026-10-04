import Combine
import Foundation

final class DriveListModel: ObservableObject, USBMonitorDelegate {
    @Published var drives: [DriveInfo] = []

    func usbMonitor(_ monitor: USBMonitor, driveAppeared drive: DriveInfo) {
        if let index = drives.firstIndex(where: { $0.bsdName == drive.bsdName }) {
            drives[index] = drive
        } else {
            drives.append(drive)
        }

        // If it's NTFS and already formatted, mount it immediately —
        // the whole point is "plug in and it just works".
        if drive.fileSystem == .ntfs {
            mount(drive)
        }
    }

    func usbMonitor(_ monitor: USBMonitor, driveDisappeared bsdName: String) {
        drives.removeAll { $0.bsdName == bsdName }
    }

    func formatAsNTFS(_ drive: DriveInfo) {
        updateState(drive.bsdName, to: .formatting)
        NTFSManager.shared.format(drive: drive, volumeName: drive.volumeName) { [weak self] result in
            switch result {
            case .success:
                self?.mount(drive)
            case .failure(let error):
                self?.updateState(drive.bsdName, to: .failed(error.localizedDescription))
            }
        }
    }

    func mount(_ drive: DriveInfo) {
        updateState(drive.bsdName, to: .mounting)
        NTFSManager.shared.mount(drive: drive) { [weak self] result in
            switch result {
            case .success(let path):
                self?.updateState(drive.bsdName, to: .mounted(path: path))
            case .failure(let error):
                self?.updateState(drive.bsdName, to: .failed(error.localizedDescription))
            }
        }
    }

    func unmount(_ drive: DriveInfo) {
        guard case .mounted(let path) = drive.state else { return }
        NTFSManager.shared.unmount(mountPoint: path) { [weak self] result in
            switch result {
            case .success:
                self?.updateState(drive.bsdName, to: .unmounted)
            case .failure(let error):
                self?.updateState(drive.bsdName, to: .failed(error.localizedDescription))
            }
        }
    }

    private func updateState(_ bsdName: String, to state: DriveInfo.MountState) {
        guard let index = drives.firstIndex(where: { $0.bsdName == bsdName }) else { return }
        drives[index].state = state
    }
}
