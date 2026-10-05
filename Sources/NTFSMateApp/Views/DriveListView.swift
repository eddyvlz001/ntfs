import SwiftUI

struct DriveListView: View {
    @ObservedObject var model: DriveListModel
    var onOpenMainWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("NTFSMate").font(.headline)
                Spacer()
                Button {
                    model.refreshDiagnostics()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Volver a comprobar el servicio y las herramientas")
            }
            .padding(12)
            Divider()

            if let diagnosis = model.helperDiagnosis {
                DiagnosisBanner(
                    icon: "exclamationmark.triangle.fill",
                    message: diagnosis,
                    actionTitle: "Abrir Ajustes del Sistema"
                ) {
                    model.openLoginItemsSettings()
                }
                Divider()
            } else if model.toolsMissing {
                DiagnosisBanner(
                    icon: "exclamationmark.triangle.fill",
                    message: "Falta macFUSE y/o ntfs-3g. Corre Scripts/install-dependencies.sh en una Terminal y vuelve a intentar.",
                    actionTitle: nil,
                    action: nil
                )
                Divider()
            }

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

            Divider()
            HStack {
                Button("Abrir ventana principal") { onOpenMainWindow() }
                Spacer()
                Button("Salir") { NSApp.terminate(nil) }
            }
            .padding(12)
        }
        .frame(width: 340)
        .alert(
            "Error",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }
}

private struct DiagnosisBanner: View {
    let icon: String
    let message: String
    let actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon).foregroundStyle(.orange)
                Text(message).font(.caption)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.caption)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
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
            Text(drive.statusLabel).font(.caption).foregroundStyle(statusColor)

            HStack {
                switch drive.fileSystem {
                case .unformatted, .other:
                    Button("Formatear como NTFS") { model.formatAsNTFS(drive) }
                        .disabled(isBusy)
                case .ntfs:
                    switch drive.state {
                    case .mounted:
                        Button("Expulsar") { model.unmount(drive) }
                    default:
                        Button("Montar") { model.mount(drive) }
                            .disabled(isBusy)
                    }
                }
                if isBusy {
                    ProgressView().controlSize(.small).padding(.leading, 4)
                }
            }
            .font(.caption)
        }
        .padding(12)
    }

    private var isBusy: Bool {
        switch drive.state {
        case .formatting, .mounting: return true
        default: return false
        }
    }

    private var statusColor: Color {
        if case .failed = drive.state { return .red }
        return .secondary
    }
}
