import Foundation

struct DriveInfo: Identifiable, Equatable {
    enum FileSystem: Equatable {
        case ntfs
        case other(String)
        case unformatted
    }

    enum MountState: Equatable {
        case unmounted
        case mounting
        case mounted(path: String)
        case formatting
        case failed(String)
    }

    var id: String { bsdName }

    let bsdName: String
    let volumeName: String
    let fileSystem: FileSystem
    let sizeBytes: UInt64
    let isRemovable: Bool
    var state: MountState = .unmounted

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}
