import SwiftUI

struct DriveListView: View {
    @ObservedObject var model: DriveListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NTFSMate").font(.headline).padding(12)
            Divider()

            if model.drives.isEmpty {
                Text("Sin unidades USB conectadas")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(model.drives) { drive in
                    DriveRow(drive: drive, model: model)
                    Divider()
                }
            }

            Button("Salir") { NSApp.terminate(nil) }
                .padding(12)
        }
        .frame(width: 320)
    }
}

private struct DriveRow: View {
    let drive: DriveInfo
    @ObservedObject var model: DriveListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(drive.volumeName).bold()
                Spacer()
                Text(drive.sizeDescription).foregroundStyle(.secondary).font(.caption)
            }
            Text(statusText).font(.caption).foregroundStyle(.secondary)

            HStack {
                switch drive.fileSystem {
                case .unformatted, .other:
                    Button("Formatear como NTFS") { model.formatAsNTFS(drive) }
                case .ntfs:
                    switch drive.state {
                    case .mounted:
                        Button("Expulsar") { model.unmount(drive) }
                    default:
                        Button("Montar") { model.mount(drive) }
                    }
                }
            }
            .font(.caption)
        }
        .padding(12)
    }

    private var statusText: String {
        switch drive.state {
        case .unmounted: return "Desmontada"
        case .mounting: return "Montando…"
        case .mounted(let path): return "Montada en \(path)"
        case .formatting: return "Formateando…"
        case .failed(let message): return "Error: \(message)"
        }
    }
}
