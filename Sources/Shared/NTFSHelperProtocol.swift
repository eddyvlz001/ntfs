import Foundation

/// Mach service name the privileged helper listens on and the app connects to.
public let helperMachServiceName = "com.ntfsmate.helper"

/// XPC contract between NTFSMate.app (unprivileged) and NTFSHelper (root daemon).
/// Every privileged disk operation (format, mount, unmount) must go through here —
/// the app itself never shells out to disk tools directly.
@objc public protocol NTFSHelperProtocol {
    func toolPaths(withReply reply: @escaping ([String: String]) -> Void)

    func formatDisk(
        bsdName: String,
        volumeName: String,
        quickFormat: Bool,
        clusterSizeKB: Int,
        withReply reply: @escaping (Bool, String?) -> Void
    )

    func mountNTFS(
        bsdName: String,
        mountPoint: String,
        withReply reply: @escaping (Bool, String?) -> Void
    )

    func unmountNTFS(
        mountPoint: String,
        withReply reply: @escaping (Bool, String?) -> Void
    )
}

/// Candidate install locations for the macFUSE/ntfs-3g CLI tools, in priority order.
/// Covers Homebrew on Apple Silicon (/opt/homebrew) and Intel (/usr/local), plus the
/// gromgit/fuse tap's install prefix for ntfs-3g-mac.
public enum NTFSToolLocator {
    public static let mkntfsCandidates = [
        "/usr/local/bin/mkntfs",
        "/usr/local/opt/ntfs-3g-mac/sbin/mkntfs",
        "/opt/homebrew/bin/mkntfs",
        "/opt/homebrew/opt/ntfs-3g-mac/sbin/mkntfs",
    ]

    public static let ntfs3gCandidates = [
        "/usr/local/bin/ntfs-3g",
        "/usr/local/opt/ntfs-3g-mac/bin/ntfs-3g",
        "/opt/homebrew/bin/ntfs-3g",
        "/opt/homebrew/opt/ntfs-3g-mac/bin/ntfs-3g",
    ]

    public static func firstExisting(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
