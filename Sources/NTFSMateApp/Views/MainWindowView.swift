import SwiftUI

/// Full window, Paragon-style: sidebar lists every detected drive, the
/// detail pane on the right shows info + a toolbar of actions for whichever
/// one is selected. The menu bar popover stays as the lightweight quick
/// mount/eject surface — this is the "open the real app" window.
struct MainWindowView: View {
    @ObservedObject var model: DriveListModel
    @State private var selection: String?

    var body: some View {
        NavigationSplitView {
            List(model.drives, selection: $selection) { drive in
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive.fill")
                        .foregroundStyle(iconColor(for: drive))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(drive.volumeName)
                        Text(drive.fileSystemLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .overlay {
                if model.drives.isEmpty {
                    PlaceholderView(
                        icon: "externaldrive.badge.questionmark",
                        title: "Sin unidades USB",
                        subtitle: "Conecta una unidad para verla aquí."
                    )
                }
            }
        } detail: {
            if let drive = model.drives.first(where: { $0.bsdName == selection }) {
                DriveDetailView(drive: drive, model: model)
            } else {
                PlaceholderView(
                    icon: "sidebar.left",
                    title: "Selecciona una unidad",
                    subtitle: "Elige una unidad de la lista para ver sus detalles."
                )
            }
        }
        .frame(minWidth: 680, minHeight: 420)
        .onAppear { model.refreshDiagnostics() }
        .onChange(of: model.drives) { drives in
            if selection == nil { selection = drives.first?.bsdName }
        }
    }

    private func iconColor(for drive: DriveInfo) -> Color {
        if case .mounted = drive.state { return .accentColor }
        if case .failed = drive.state { return .red }
        return .secondary
    }
}

private struct DriveDetailView: View {
    let drive: DriveInfo
    @ObservedObject var model: DriveListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let diagnosis = model.helperDiagnosis {
                Label(diagnosis, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 14) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(drive.volumeName).font(.title2).bold()
                    Text(drive.statusLabel).foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                InfoRow(label: "Sistema de archivos", value: drive.fileSystemLabel)
                InfoRow(label: "Tamaño", value: drive.sizeDescription)
                InfoRow(label: "Dispositivo", value: "/dev/\(drive.bsdName)")
                InfoRow(label: "Removible", value: drive.isRemovable ? "Sí" : "No")
            }

            Divider()

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
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var isBusy: Bool {
        switch drive.state {
        case .formatting, .mounting: return true
        default: return false
        }
    }
}

private struct PlaceholderView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
