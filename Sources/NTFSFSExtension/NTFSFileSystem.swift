import FSKit

/// Entry point FSKit calls into. One instance handles probing and loading
/// whatever block device the user picks to mount as NTFS.
///
/// VERIFY AGAINST XCODE: this file was written against FSKit's public API
/// surface as documented by Apple, without access to the real SDK headers in
/// this environment. `probeResource`/`loadResource` signatures are correct
/// per https://developer.apple.com/documentation/fskit/fsunaryfilesystemoperations
/// as of this writing, but exact reply-handler payload types should be
/// confirmed against Xcode's autocomplete once this lives inside a target
/// created from the "File System Extension" template.
final class NTFSFileSystem: FSUnaryFileSystem, FSUnaryFileSystemOperations {

    func probeResource(
        resource: FSResource,
        replyHandler: @escaping (FSProbeResult?, Error?) -> Void
    ) {
        guard let blockResource = resource as? FSBlockDeviceResource else {
            replyHandler(nil, NTFSEngineError.unsupportedResource)
            return
        }

        // Probing mounts read-only and immediately unmounts — ntfs_mount()
        // itself is the signature check; there's no cheaper way to ask
        // libntfs-3g "is this NTFS?" without duplicating its boot-sector logic.
        if NTFSEngine.probe(blockResource) {
            replyHandler(.init(result: .recognized, name: "NTFS", containerID: nil), nil)
        } else {
            replyHandler(.init(result: .notRecognized), nil)
        }
    }

    func loadResource(
        resource: FSResource,
        options: FSTaskOptions,
        replyHandler: @escaping (FSVolume?, Error?) -> Void
    ) {
        guard let blockResource = resource as? FSBlockDeviceResource else {
            replyHandler(nil, NTFSEngineError.unsupportedResource)
            return
        }

        do {
            let volume = try NTFSVolume(blockResource: blockResource)
            replyHandler(volume, nil)
        } catch {
            replyHandler(nil, error)
        }
    }
}
