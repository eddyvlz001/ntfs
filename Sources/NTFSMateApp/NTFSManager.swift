import Foundation
import ServiceManagement

/// App-side gateway to the privileged helper. Owns helper registration
/// (SMAppService, macOS 13+) and the XPC connection; all format/mount calls
/// go through here so the rest of the app never touches Process/XPC directly.
final class NTFSManager {
    static let shared = NTFSManager()

    private var connection: NSXPCConnection?

    enum ManagerError: LocalizedError {
        case helperUnavailable
        case toolsMissing

        var errorDescription: String? {
            switch self {
            case .helperUnavailable:
                return "No se pudo conectar con el servicio privilegiado NTFSHelper."
            case .toolsMissing:
                return "Faltan macFUSE y/o ntfs-3g. Ejecuta Scripts/install-dependencies.sh."
            }
        }
    }

    /// Registers and approves the privileged daemon. Must be called once at app
    /// launch; on first run this prompts the user in System Settings.
    func registerHelperIfNeeded() throws {
        let service = SMAppService.daemon(plistName: "com.ntfsmate.helper.plist")
        switch service.status {
        case .enabled:
            return
        case .notRegistered, .requiresApproval:
            try service.register()
        case .notFound:
            throw ManagerError.helperUnavailable
        @unknown default:
            try service.register()
        }
    }

    func checkToolsInstalled(completion: @escaping (Bool) -> Void) {
        proxy { helper in
            helper?.toolPaths { paths in
                DispatchQueue.main.async {
                    completion(paths["mkntfs"] != nil && paths["ntfs-3g"] != nil)
                }
            }
        }
    }

    func format(drive: DriveInfo, volumeName: String, quickFormat: Bool = true, completion: @escaping (Result<Void, Error>) -> Void) {
        proxy { helper in
            guard let helper else {
                DispatchQueue.main.async { completion(.failure(ManagerError.helperUnavailable)) }
                return
            }
            // 4K clusters are NTFS's sweet spot for mixed file-size workloads;
            // larger clusters only help with purely large sequential files.
            helper.formatDisk(bsdName: drive.bsdName, volumeName: volumeName, quickFormat: quickFormat, clusterSizeKB: 4) { success, output in
                DispatchQueue.main.async {
                    success ? completion(.success(())) : completion(.failure(NSError(domain: "NTFSMate", code: 1, userInfo: [NSLocalizedDescriptionKey: output ?? "Formateo fallido"])))
                }
            }
        }
    }

    func mount(drive: DriveInfo, completion: @escaping (Result<String, Error>) -> Void) {
        let mountPoint = "/Volumes/\(drive.volumeName)"
        proxy { helper in
            guard let helper else {
                DispatchQueue.main.async { completion(.failure(ManagerError.helperUnavailable)) }
                return
            }
            helper.mountNTFS(bsdName: drive.bsdName, mountPoint: mountPoint) { success, output in
                DispatchQueue.main.async {
                    success ? completion(.success(mountPoint)) : completion(.failure(NSError(domain: "NTFSMate", code: 2, userInfo: [NSLocalizedDescriptionKey: output ?? "Montaje fallido"])))
                }
            }
        }
    }

    func unmount(mountPoint: String, completion: @escaping (Result<Void, Error>) -> Void) {
        proxy { helper in
            guard let helper else {
                DispatchQueue.main.async { completion(.failure(ManagerError.helperUnavailable)) }
                return
            }
            helper.unmountNTFS(mountPoint: mountPoint) { success, output in
                DispatchQueue.main.async {
                    success ? completion(.success(())) : completion(.failure(NSError(domain: "NTFSMate", code: 3, userInfo: [NSLocalizedDescriptionKey: output ?? "Desmontaje fallido"])))
                }
            }
        }
    }

    // MARK: - XPC plumbing

    private func proxy(_ body: @escaping (NTFSHelperProtocol?) -> Void) {
        if connection == nil {
            let conn = NSXPCConnection(machServiceName: helperMachServiceName, options: .privileged)
            conn.remoteObjectInterface = NSXPCInterface(with: NTFSHelperProtocol.self)
            conn.invalidationHandler = { [weak self] in self?.connection = nil }
            conn.interruptionHandler = { [weak self] in self?.connection = nil }
            conn.resume()
            connection = conn
        }
        let proxy = connection?.remoteObjectProxyWithErrorHandler { _ in body(nil) } as? NTFSHelperProtocol
        body(proxy)
    }
}
