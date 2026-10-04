import FSKit

/// One mounted NTFS volume. Delegates every actual filesystem operation to
/// `NTFSEngine` (libntfs-3g linked in-process) — this class's job is just to
/// translate between FSKit's item/path model and libntfs-3g's MFT-reference
/// model.
///
/// VERIFY AGAINST XCODE: `lookupItem` below matches the signature confirmed
/// against Apple's published FSKit docs. The read/write/attribute methods
/// are written against `FSVolume.ReadWriteHandler` / `FSVolume.Handler` as
/// publicly documented, but exact closure payload types (the `FSItem.Attributes`
/// builder in particular) should be confirmed against Xcode's autocomplete —
/// this framework is new enough that Apple has adjusted exact signatures
/// between point releases.
final class NTFSVolume: FSVolume {

    private let engine: NTFSEngine

    init(blockResource: FSBlockDeviceResource) throws {
        guard let bsdName = blockResource.value(forKey: "bsdName") as? String else {
            throw NTFSEngineError.unsupportedResource
        }
        engine = NTFSEngine(devicePath: "/dev/\(bsdName)")
        super.init()
        try engine.mount()
    }

    deinit {
        engine.unmount()
    }
}

extension NTFSVolume: FSVolume.PathConfOperations {
    var maximumLinkCount: Int { 1 }
    var maximumNameLength: Int { 255 }
    var restrictsOwnershipChanges: Bool { false }
    var truncatesLongNames: Bool { false }
    var maximumFileSize: UInt64 { UInt64.max }
}

extension NTFSVolume: FSVolume.Handler {
    func lookupItem(
        named name: FSFileName,
        in directory: FSItem,
        context: FSTaskContext,
        replyHandler: @escaping (FSLookupItemResult?, Error?) -> Void
    ) {
        // TODO: build the full path by walking from `directory` (FSKit gives
        // you the parent FSItem, not a string path) and pass that to
        // engine.inode(atPath:). Placeholder until the real FSItem ->
        // path-segment accessor is confirmed in Xcode.
        replyHandler(nil, NTFSEngineError.inodeNotFound(0))
    }
}

extension NTFSVolume: FSVolume.ReadWriteHandler {
    func read(
        from item: FSItem,
        at offset: Int64,
        length: Int,
        into buffer: FSMutableFileDataBuffer,
        context: FSTaskContext,
        replyHandler: @escaping (Int, Error?) -> Void
    ) {
        // TODO: resolve `item` back to its MFT reference (FSKit identifies
        // items by FSItem.Identifier — map that to the UInt64 mft_no this
        // engine expects, likely via a lookup table populated in lookupItem).
        replyHandler(0, NTFSEngineError.ioError("not implemented"))
    }

    func write(
        contents: FSFileDataBuffer,
        to item: FSItem,
        at offset: Int64,
        context: FSTaskContext,
        replyHandler: @escaping (Int, Error?) -> Void
    ) {
        replyHandler(0, NTFSEngineError.ioError("not implemented"))
    }
}
