import ArrangerLabCore
import SwiftUI
import UniformTypeIdentifiers

struct KORGMediaInspectorView: View {
    @State private var inventory: KORGMediaInventory?
    @State private var scanProgress: KORGMediaScanProgress?
    @State private var scanTask: Task<Void, Never>?
    @State private var activeScanID: UUID?
    @State private var searchText = ""
    @State private var resourceFilter: KORGMediaResourceKind?
    @State private var statusFilter: KORGMediaItemStatus?
    @State private var isImporterPresented = false
    @State private var isExporterPresented = false
    @State private var reportDocument: KORGMediaReportDocument?
    @State private var errorMessage: String?

    private var filteredItems: [KORGMediaItem] {
        guard let inventory else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return inventory.items.filter { item in
            if let resourceFilter, item.resourceKind != resourceFilter { return false }
            if let statusFilter, item.status != statusFilter { return false }
            guard !query.isEmpty else { return true }
            return item.relativePath.localizedCaseInsensitiveContains(query)
                || item.resourceKind.displayName.localizedCaseInsensitiveContains(query)
                || item.status.displayName.localizedCaseInsensitiveContains(query)
                || item.functionalDirectory?.localizedCaseInsensitiveContains(query) == true
        }
    }

    private var isScanning: Bool { scanTask != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "Mídia KORG",
                subtitle: "Inventário somente leitura de uma pasta .SET ou recurso avulso. Nenhum conteúdo é instalado, extraído, convertido ou descriptografado."
            )

            HStack(spacing: 10) {
                Button("Selecionar mídia…", systemImage: "externaldrive.badge.plus") {
                    isImporterPresented = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)

                if isScanning {
                    Button("Cancelar", role: .cancel) { cancelScan() }
                    ProgressView()
                        .controlSize(.small)
                    if let scanProgress {
                        Text("\(scanProgress.discoveredItemCount) itens")
                            .font(.callout.monospacedDigit())
                        Text(scanProgress.currentRelativePath ?? "")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Button("Exportar JSON", systemImage: "square.and.arrow.up") {
                        prepareExport()
                    }
                    .disabled(inventory == nil)
                    Button("Limpar") { clearInventory() }
                        .disabled(inventory == nil)
                }

                Spacer()
                Label("Metadados apenas", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let inventory {
                summary(for: inventory)
                filters
                Table(filteredItems) {
                    TableColumn("Recurso") { item in
                        Text(URL(fileURLWithPath: item.relativePath).lastPathComponent)
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 170)

                    TableColumn("Tipo") { item in
                        Text(item.resourceKind.displayName)
                    }
                    .width(min: 90, ideal: 130)

                    TableColumn("Caminho") { item in
                        Text(item.relativePath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .width(min: 220, ideal: 360)

                    TableColumn("Tamanho") { item in
                        Text(byteCount(item.sizeBytes))
                            .monospacedDigit()
                    }
                    .width(90)

                    TableColumn("Status") { item in
                        Label(item.status.displayName, systemImage: statusIcon(item.status))
                            .foregroundStyle(statusColor(item.status))
                    }
                    .width(min: 100, ideal: 125)

                    TableColumn("Avisos") { item in
                        Text(item.warnings.isEmpty ? "—" : "\(item.warnings.count)")
                            .foregroundStyle(item.warnings.isEmpty ? .secondary : LabTheme.draft)
                    }
                    .width(65)
                }

                warnings(for: inventory)
            } else if !isScanning {
                ContentUnavailableView(
                    "Nenhuma mídia inspecionada",
                    systemImage: "externaldrive",
                    description: Text("Selecione uma pasta .SET ou um recurso KORG reconhecido.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.folder, .data],
            allowsMultipleSelection: false,
            onCompletion: importSelection
        )
        .fileExporter(
            isPresented: $isExporterPresented,
            document: reportDocument,
            contentType: .json,
            defaultFilename: exportFilename,
            onCompletion: exportCompleted
        )
        .alert(
            "Mídia KORG",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear { cancelScan() }
    }

    @ViewBuilder
    private func summary(for inventory: KORGMediaInventory) -> some View {
        HStack(spacing: 12) {
            summaryCard(
                title: "Origem",
                value: inventory.sourceName,
                detail: inventory.containerKind.displayName
            )
            summaryCard(
                title: "Itens",
                value: "\(inventory.summary.itemCount)",
                detail: byteCount(inventory.summary.totalBytes)
            )
            summaryCard(
                title: "Proprietários",
                value: "\(inventory.items.filter { $0.status == .opaque }.count)",
                detail: "catalogados, não decodificados"
            )
            summaryCard(
                title: "Atenção",
                value: "\(inventory.items.filter { [.unknown, .unreadable, .skipped].contains($0.status) }.count)",
                detail: "desconhecidos ou ignorados"
            )
        }
    }

    private func summaryCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var filters: some View {
        HStack(spacing: 12) {
            TextField("Buscar nome, caminho, tipo ou diretório", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)

            Picker("Tipo", selection: $resourceFilter) {
                Text("Todos os tipos").tag(KORGMediaResourceKind?.none)
                ForEach(KORGMediaResourceKind.allCases) { kind in
                    Text(kind.displayName).tag(Optional(kind))
                }
            }
            .frame(width: 190)

            Picker("Status", selection: $statusFilter) {
                Text("Todos os status").tag(KORGMediaItemStatus?.none)
                ForEach(KORGMediaItemStatus.allCases) { status in
                    Text(status.displayName).tag(Optional(status))
                }
            }
            .frame(width: 170)

            Spacer()
            Text("\(filteredItems.count) exibidos")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func warnings(for inventory: KORGMediaInventory) -> some View {
        let itemWarnings = inventory.items.flatMap { item in
            item.warnings.map { "\(item.relativePath): \($0)" }
        }
        let allWarnings = inventory.warnings + itemWarnings
        if !allWarnings.isEmpty {
            DisclosureGroup("\(allWarnings.count) avisos de inventário") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(allWarnings.enumerated()), id: \.offset) { _, warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }
                .frame(maxHeight: 120)
            }
        }
    }

    private var exportFilename: String {
        guard let sourceName = inventory?.sourceName else { return "korg-media-inventory.json" }
        return "\(sourceName)-inventory.json"
    }

    private func importSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            startScan(url)
        case let .failure(error):
            if (error as NSError).code != NSUserCancelledError {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startScan(_ url: URL) {
        cancelScan()
        inventory = nil
        scanProgress = .init(discoveredItemCount: 0, discoveredBytes: 0, currentRelativePath: nil)
        searchText = ""
        resourceFilter = nil
        statusFilter = nil

        let scanID = UUID()
        activeScanID = scanID
        scanTask = Task {
            do {
                let result = try await KORGMediaScanner().scan(at: url) { progress in
                    guard progress.discoveredItemCount == 1
                            || progress.discoveredItemCount.isMultiple(of: 64) else { return }
                    Task { @MainActor in
                        guard activeScanID == scanID else { return }
                        scanProgress = progress
                    }
                }
                try Task.checkCancellation()
                guard activeScanID == scanID else { return }
                inventory = result
                scanProgress = nil
                scanTask = nil
                activeScanID = nil
            } catch is CancellationError {
                guard activeScanID == scanID else { return }
                scanProgress = nil
                scanTask = nil
                activeScanID = nil
            } catch {
                guard activeScanID == scanID else { return }
                scanProgress = nil
                scanTask = nil
                activeScanID = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelScan() {
        activeScanID = nil
        scanTask?.cancel()
        scanTask = nil
        scanProgress = nil
    }

    private func clearInventory() {
        cancelScan()
        inventory = nil
        reportDocument = nil
        searchText = ""
        resourceFilter = nil
        statusFilter = nil
    }

    private func prepareExport() {
        guard let inventory else { return }
        do {
            reportDocument = KORGMediaReportDocument(data: try inventory.jsonData())
            isExporterPresented = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportCompleted(_ result: Result<URL, Error>) {
        if case let .failure(error) = result,
           (error as NSError).code != NSUserCancelledError {
            errorMessage = error.localizedDescription
        }
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func statusIcon(_ status: KORGMediaItemStatus) -> String {
        switch status {
        case .recognized: return "checkmark.circle"
        case .opaque: return "lock"
        case .unknown: return "questionmark.circle"
        case .unreadable: return "exclamationmark.triangle"
        case .skipped: return "nosign"
        }
    }

    private func statusColor(_ status: KORGMediaItemStatus) -> Color {
        switch status {
        case .recognized: return LabTheme.verified
        case .opaque: return LabTheme.draft
        case .unknown, .unreadable, .skipped: return .secondary
        }
    }
}

private struct KORGMediaReportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
