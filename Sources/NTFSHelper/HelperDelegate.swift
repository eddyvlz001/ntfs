import Foundation

/// Implements the privileged side of the XPC contract. This process runs as root
/// (launchd daemon), so every input here is attacker-controlled from the app's
/// perspective — arguments are passed to Process via argv arrays (never through a
/// shell), and bsdName/mountPoint are validated before use.
final class HelperDelegate: NSObject, NTFSHelperProtocol, NSXPCListenerDelegate {

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: NTFSHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func toolPaths(withReply reply: @escaping ([String: String]) -> Void) {
        var result: [String: String] = [:]
        if let mkntfs = NTFSToolLocator.firstExisting(NTFSToolLocator.mkntfsCandidates) {
            result["mkntfs"] = mkntfs
        }
        if let ntfs3g = NTFSToolLocator.firstExisting(NTFSToolLocator.ntfs3gCandidates) {
            result["ntfs-3g"] = ntfs3g
        }
        reply(result)
    }

    func formatDisk(
        bsdName: String,
        volumeName: String,
        quickFormat: Bool,
        clusterSizeKB: Int,
        withReply reply: @escaping (Bool, String?) -> Void
    ) {
        guard isValidBSDName(bsdName) else {
            reply(false, "Invalid device identifier")
            return
        }
        guard let mkntfs = NTFSToolLocator.firstExisting(NTFSToolLocator.mkntfsCandidates) else {
            reply(false, "mkntfs not found — install ntfs-3g-mac")
            return
        }

        let devicePath = "/dev/\(bsdName)"

        // Unmount first; mkntfs refuses to write to a mounted device.
        runDiskutil(["unmountDisk", devicePath]) { _, _ in
            var args = ["-f", "-L", volumeName]
            if quickFormat { args.append("-Q") }
            if clusterSizeKB > 0 { args.append(contentsOf: ["-c", "\(clusterSizeKB * 1024)"]) }
            args.append(devicePath)

            self.run(mkntfs, args) { success, output in
                reply(success, output)
            }
        }
    }

    func mountNTFS(bsdName: String, mountPoint: String, withReply reply: @escaping (Bool, String?) -> Void) {
        guard isValidBSDName(bsdName) else {
            reply(false, "Invalid device identifier")
            return
        }
        guard let ntfs3g = NTFSToolLocator.firstExisting(NTFSToolLocator.ntfs3gCandidates) else {
            reply(false, "ntfs-3g not found — install ntfs-3g-mac")
            return
        }

        let fm = FileManager.default
        try? fm.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

        // Performance options for the legacy macFUSE kext path on Intel:
        // kernel_cache + auto_cache let the kernel cache pages instead of round-tripping
        // every read through the FUSE daemon; big_writes raises the write buffer well
        // past FUSE's old 4K default; a large blksize cuts syscall overhead for
        // large sequential transfers (the common USB backup/media case).
        let mountOptions = "volname=NTFSMate,local,allow_other,auto_xattr,big_writes,kernel_cache,auto_cache,blksize=1048576,noatime"

        let args = ["/dev/\(bsdName)", mountPoint, "-o", mountOptions]
        run(ntfs3g, args) { success, output in
            reply(success, output)
        }
    }

    func unmountNTFS(mountPoint: String, withReply reply: @escaping (Bool, String?) -> Void) {
        run("/sbin/umount", [mountPoint]) { success, output in
            reply(success, output)
        }
    }

    // MARK: - Helpers

    private func isValidBSDName(_ name: String) -> Bool {
        // e.g. disk4s1 — refuse anything that isn't a plain BSD disk identifier.
        let pattern = "^disk[0-9]+(s[0-9]+)?$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    private func runDiskutil(_ args: [String], completion: @escaping (Bool, String?) -> Void) {
        run("/usr/sbin/diskutil", args, completion: completion)
    }

    private func run(_ executablePath: String, _ args: [String], completion: @escaping (Bool, String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            completion(false, error.localizedDescription)
            return
        }

        process.terminationHandler = { proc in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)
            completion(proc.terminationStatus == 0, output)
        }
    }
}
