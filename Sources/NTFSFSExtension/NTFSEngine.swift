import FSKit
import Foundation

enum NTFSEngineError: Error {
    case unsupportedResource
    case probeFailed
    case mountFailed(String)
    case inodeNotFound(UInt64)
    case ioError(String)
}

/// Thin Swift wrapper over libntfs-3g, linked directly into this extension's
/// process so NTFS parsing/writing runs in-process with no FUSE/subprocess hop.
///
/// NOT VERIFIED IN XCODE: `bsdDevicePath(for:)` assumes FSBlockDeviceResource
/// exposes (directly or via a property FSKit adds at runtime) the BSD device
/// special file path, e.g. "/dev/rdisk4s1" — the same thing a kext driver
/// would have received as a dev_t. Confirm the real accessor once this is
/// dropped into a target generated from Xcode's File System Extension
/// template; libntfs-3g's own functions below (ntfs_mount, ntfs_attr_pread,
/// etc.) are stable, long-documented C APIs and are the part of this file
/// safe to trust as written.
final class NTFSEngine {

    private var volume: UnsafeMutablePointer<ntfs_volume>?
    private let devicePath: String

    init(devicePath: String) {
        self.devicePath = devicePath
    }

    static func probe(_ resource: FSBlockDeviceResource) -> Bool {
        guard let path = bsdDevicePath(for: resource) else { return false }
        // NTFS_MNT_RDONLY | NTFS_MNT_EXCLUSIVE — read-only probe, refuse if
        // something else already has it open.
        guard let vol = ntfs_mount(path, NTFS_MNT_RDONLY) else { return false }
        ntfs_umount(vol, true)
        return true
    }

    func mount() throws {
        guard volume == nil else { return }
        guard let vol = ntfs_mount(devicePath, ntfs_mount_flags(0)) else {
            throw NTFSEngineError.mountFailed(String(cString: strerror(errno)))
        }
        volume = vol
    }

    func unmount() {
        guard let vol = volume else { return }
        ntfs_umount(vol, false)
        volume = nil
    }

    /// Resolves an absolute NTFS path (e.g. "/Users/x/file.txt") to an MFT
    /// reference, the stable identifier FSKit items should key off of.
    func inode(atPath path: String) throws -> UInt64 {
        guard let vol = volume else { throw NTFSEngineError.mountFailed("not mounted") }
        guard let ni = ntfs_pathname_to_inode(vol, nil, path) else {
            throw NTFSEngineError.inodeNotFound(0)
        }
        defer { ntfs_inode_close(ni) }
        return ni.pointee.mft_no
    }

    func read(mftReference: UInt64, offset: Int64, length: Int, into buffer: UnsafeMutableRawPointer) throws -> Int {
        guard let vol = volume else { throw NTFSEngineError.mountFailed("not mounted") }
        guard let ni = ntfs_inode_open(vol, mftReference) else {
            throw NTFSEngineError.inodeNotFound(mftReference)
        }
        defer { ntfs_inode_close(ni) }

        guard let attr = ntfs_attr_open(ni, AT_DATA, nil, 0) else {
            throw NTFSEngineError.ioError("no $DATA attribute")
        }
        defer { ntfs_attr_close(attr) }

        let bytesRead = ntfs_attr_pread(attr, offset, Int64(length), buffer)
        guard bytesRead >= 0 else {
            throw NTFSEngineError.ioError(String(cString: strerror(errno)))
        }
        return Int(bytesRead)
    }

    func write(mftReference: UInt64, offset: Int64, length: Int, from buffer: UnsafeRawPointer) throws -> Int {
        guard let vol = volume else { throw NTFSEngineError.mountFailed("not mounted") }
        guard let ni = ntfs_inode_open(vol, mftReference) else {
            throw NTFSEngineError.inodeNotFound(mftReference)
        }
        defer { ntfs_inode_close(ni) }

        guard let attr = ntfs_attr_open(ni, AT_DATA, nil, 0) else {
            throw NTFSEngineError.ioError("no $DATA attribute")
        }
        defer { ntfs_attr_close(attr) }

        let bytesWritten = ntfs_attr_pwrite(attr, offset, Int64(length), buffer)
        guard bytesWritten >= 0 else {
            throw NTFSEngineError.ioError(String(cString: strerror(errno)))
        }
        return Int(bytesWritten)
    }

    private static func bsdDevicePath(for resource: FSBlockDeviceResource) -> String? {
        // TODO: replace with the real FSBlockDeviceResource accessor — see
        // the type's doc comment above. Placeholder keeps this file
        // structurally complete without inventing a method that doesn't
        // exist on the real class.
        guard let bsdName = resource.value(forKey: "bsdName") as? String else { return nil }
        return "/dev/\(bsdName)"
    }
}
