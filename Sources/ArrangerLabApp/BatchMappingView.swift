import ArrangerLabCore
import SwiftUI

struct BatchMappingView: View {
    private enum LibraryFilter: String, CaseIterable, Identifiable {
        case all = "Todos"
        case factory = "Factory"
        case legacy = "Legacy"
        case gmXG = "GM/XG"
        case user = "User"

        var id: Self { self }
    }

    private enum NamingMode: String, CaseIterable, Identifiable {
        case photo = "Por foto"
        case live = "Um por vez"

        var id: Self { self }
    }

    @EnvironmentObject private var model: AppModel
    @State private var confirmNewSession = false
    @State private var namingMode: NamingMode = .photo
    @State private var selectedScreenID: UUID?
    @State private var bulkNames = ""
    @State private var libraryFilter: LibraryFilter = .all
    @FocusState private var quickNameID: String?

    private var displayEntries: [BatchSoundEntry] {
        model.batchSoundEntries.filter { entry in
            switch libraryFilter {
            case .all: return true
            case .factory: return entry.library == "Factory"
            case .legacy: return entry.library == "Legacy"
            case .gmXG: return entry.library == "GM/XG"
            case .user:
                return entry.library == "User"
                    || (entry.selection.bankMSB == 121 && (64...67).contains(entry.selection.bankLSB))
            }
        }
    }
    private var completedScreens: [BatchSoundScreenCapture] {
        model.batchScreenCaptures.filter { !$0.isOpen && !$0.entryIDs.isEmpty }
    }
    private var selectedScreen: BatchSoundScreenCapture? {
        guard let selectedScreenID else { return nil }
        return model.batchScreenCaptures.first(where: { $0.id == selectedScreenID })
    }
    private var selectedEntries: [BatchSoundEntry] {
        guard let selectedScreenID else { return [] }
        return model.batchEntries(for: selectedScreenID)
    }
    private var parsedNames: [String] {
        bulkNames.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "Mapear timbres",
                subtitle: "Importe a biblioteca oficial e capture manualmente apenas sons User ou alterações locais."
            )

            sessionToolbar
            officialCatalogSection
            if model.hasCompleteOfficialSoundCatalog {
                fastValidationSection
            }

            Picker("Fluxo", selection: $namingMode) {
                ForEach(NamingMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            if namingMode == .photo {
                photoWorkflow
            } else {
                liveWorkflow
            }

            Divider()
            catalogHeader
            catalog
        }
        .confirmationDialog(
            "Começar uma nova sessão?",
            isPresented: $confirmNewSession,
            titleVisibility: .visible
        ) {
            Button("Nova sessão", role: .destructive) { model.createNewBatchMappingSession() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("A sessão atual já está salva. A tabela será limpa para uma nova captura.")
        }
        .onChange(of: model.batchCaptureCount) { _, _ in
            guard namingMode == .live, model.isBatchMapping, let latest = model.latestBatchSound else { return }
            quickNameID = latest.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? latest.id : nil
        }
        .onChange(of: model.batchScreenCaptures) { _, screens in
            guard let latestClosed = screens.last(where: { !$0.isOpen && !$0.entryIDs.isEmpty }),
                  selectedScreenID != latestClosed.id else { return }
            selectScreen(latestClosed.id)
        }
    }

    private var officialCatalogSection: some View {
        GroupBox {
            HStack(spacing: 16) {
                Image(systemName: model.hasCompleteOfficialSoundCatalog ? "checkmark.circle.fill" : "books.vertical")
                    .font(.title2)
                    .foregroundStyle(model.hasCompleteOfficialSoundCatalog ? LabTheme.verified : LabTheme.signal)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.hasCompleteOfficialSoundCatalog ? "Biblioteca oficial importada" : "Catalogar 1.727 sons em um clique")
                        .font(.headline)
                    Text("Factory 534 · Legacy 505 · GM/XG 688")
                        .foregroundStyle(.secondary)
                    Text("User tem 512 slots possíveis; capture apenas os slots ocupados no seu teclado.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.hasCompleteOfficialSoundCatalog {
                    Label("Completo", systemImage: "checkmark")
                        .foregroundStyle(LabTheme.verified)
                } else {
                    Button("Importar catálogo oficial", systemImage: "square.and.arrow.down") {
                        model.importOfficialPA700Sounds()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var fastValidationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: model.catalogValidationVerified ? "checkmark.seal.fill" : "waveform.and.magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(model.catalogValidationVerified ? LabTheme.verified : LabTheme.signal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Validação rápida do catálogo")
                            .font(.headline)
                        Text("Um som por banco MIDI + todos os User · cerca de 45 segundos")
                            .foregroundStyle(.secondary)
                        Text(model.fullCatalogVerified
                            ? "1.734 endereços aceitos; confirmações individuais continuam identificadas separadamente."
                            : "Confirma o endereçamento geral; depois você pode aceitar o catálogo por amostragem.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    if model.fullCatalogVerified {
                        VStack(alignment: .trailing, spacing: 4) {
                            Label("1.734 Verified", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(LabTheme.verified)
                            Text("\(model.batchSampleVerifiedCount) por amostragem")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if model.catalogValidationVerified {
                        VStack(alignment: .trailing, spacing: 6) {
                            Label("Bancos Verified", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(LabTheme.verified)
                            Button("Aceitar catálogo por amostragem", systemImage: "checkmark.seal") {
                                model.verifyFullCatalogFromSampling()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else if model.isCatalogValidating {
                        Button("Cancelar", role: .destructive) { model.cancelFastCatalogValidation() }
                    } else if !model.catalogValidationAwaitingConfirmation {
                        Button("Iniciar varredura", systemImage: "play.fill") {
                            model.startFastCatalogValidation()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.connected || model.isBatchMapping)
                    }
                }

                if model.isCatalogValidating {
                    ProgressView(
                        value: Double(model.catalogValidationProgress),
                        total: Double(max(model.catalogValidationTotal, 1))
                    ) {
                        Text("Tocando automaticamente · não mexa no PA700")
                    } currentValueLabel: {
                        Text("\(model.catalogValidationProgress)/\(model.catalogValidationTotal)")
                            .monospacedDigit()
                    }
                } else if model.catalogValidationAwaitingConfirmation {
                    HStack {
                        Text("Você ouviu uma sequência contínua de mudanças de timbre?")
                            .font(.headline)
                        Spacer()
                        Button("Não ouvi") { model.confirmFastCatalogValidation(heard: false) }
                        Button("Sim, ouvi", systemImage: "ear.fill") { model.confirmFastCatalogValidation(heard: true) }
                            .buttonStyle(.borderedProminent)
                    }
                } else if !model.catalogValidationVerified {
                    Label("Antes de iniciar, deixe somente Upper 1 ativo e ajuste o Master Volume para um nível confortável.", systemImage: "speaker.wave.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var sessionToolbar: some View {
        HStack(spacing: 10) {
            if model.isBatchMapping {
                Button("Encerrar sessão", systemImage: "stop.fill") { model.stopBatchMapping() }
                    .tint(LabTheme.danger)
            } else {
                Label(model.connected ? "PA700 pronto" : "PA700 desconectado", systemImage: model.connected ? "cable.connector" : "cable.connector.slash")
                    .foregroundStyle(model.connected ? LabTheme.verified : LabTheme.danger)
            }

            Button("Nova sessão", systemImage: "plus") {
                if model.batchSoundEntries.isEmpty { model.createNewBatchMappingSession() }
                else { confirmNewSession = true }
            }
            .disabled(model.isBatchMapping)

            Button("Salvar", systemImage: "square.and.arrow.down") { model.saveBatchCatalogNow() }
                .disabled(!model.hasBatchMappingSession)

            Button("Exportar Draft JSON", systemImage: "doc.badge.arrow.up") { model.exportBatchDraftProfile() }
                .disabled(model.batchSoundEntries.isEmpty || model.isBatchMapping || model.batchPendingNameCount > 0)

            if model.batchCatalogURL != nil {
                Button("Mostrar no Finder", systemImage: "folder") { model.revealBatchMappingFiles() }
            }

            Spacer()
            Text("\(model.batchSoundEntries.count) únicos · \(model.batchCaptureCount) seleções")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var photoWorkflow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                instruction(1, "Fotografe a tela")
                arrow
                instruction(2, "Comece uma tela")
                arrow
                instruction(3, "Toque em ordem ↦")
                arrow
                instruction(4, "Encerre e repita")
            }
            .font(.callout)

            HStack(spacing: 12) {
                if let active = model.activeBatchScreen {
                    Label(active.label, systemImage: "record.circle.fill")
                        .font(.headline)
                        .foregroundStyle(LabTheme.danger)
                    Text("\(active.entryIDs.count) capturados")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Button("Desfazer último", systemImage: "arrow.uturn.backward") {
                        model.undoLastBatchScreenCapture()
                    }
                    .disabled(active.entryIDs.isEmpty)
                    Button("Encerrar \(active.label)", systemImage: "checkmark") {
                        model.endBatchScreenCapture()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Começar nova tela", systemImage: "camera.viewfinder") {
                        model.beginBatchScreenCapture()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.connected)
                    Text("Depois toque os nomes visíveis da esquerda para a direita, linha por linha.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if !completedScreens.isEmpty {
                Divider()
                bulkAssignment
            }
        }
    }

    private var bulkAssignment: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cadastrar nomes da foto")
                    .font(.headline)
                Picker("Tela", selection: Binding(
                    get: { selectedScreenID ?? completedScreens.last?.id },
                    set: { if let id = $0 { selectScreen(id) } }
                )) {
                    ForEach(completedScreens) { screen in
                        Text("\(screen.label) · \(screen.entryIDs.count)").tag(Optional(screen.id))
                    }
                }
                .labelsHidden()
                .frame(width: 170)
                Spacer()
                if let screen = selectedScreen {
                    let ready = parsedNames.count == screen.entryIDs.count
                    Text("\(parsedNames.count) nomes / \(screen.entryIDs.count) timbres")
                        .foregroundStyle(ready ? LabTheme.verified : .secondary)
                        .monospacedDigit()
                }
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Cole um nome por linha, na mesma ordem dos toques")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $bulkNames)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(4)
                        if bulkNames.isEmpty {
                            Text("Concert Grand\nPop Grand\nClassic Piano")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(9)
                                .allowsHitTesting(false)
                        }
                    }
                    .background(.quaternary.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .frame(minHeight: 96, maxHeight: 130)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Ordem MIDI capturada")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(selectedEntries.enumerated()), id: \.offset) { index, entry in
                                Text("\(index + 1).  \(entry.selection.bankMSB).\(entry.selection.bankLSB).\(entry.selection.program)")
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: 190)
                    .frame(minHeight: 96, maxHeight: 130)
                }

                Button("Cadastrar tela", systemImage: "text.badge.checkmark") {
                    guard let selectedScreenID,
                          model.applyBatchScreenNames(screenID: selectedScreenID, names: parsedNames) else { return }
                    loadNames(for: selectedScreenID)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedScreen == nil || parsedNames.count != selectedScreen?.entryIDs.count)
                .padding(.top, 22)
            }
        }
    }

    @ViewBuilder
    private var liveWorkflow: some View {
        HStack(spacing: 10) {
            if model.isBatchMapping {
                Label("Capturando", systemImage: "record.circle.fill")
                    .foregroundStyle(LabTheme.danger)
            } else {
                Button("Iniciar captura", systemImage: "record.circle") { model.startBatchMapping() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.connected)
            }
            Text("Selecione um timbre no PA700, digite o nome abaixo e pressione Enter.")
                .foregroundStyle(.secondary)
        }

        if let latest = model.latestBatchSound {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Último timbre").font(.headline)
                    Text("CC0 \(latest.selection.bankMSB)  ·  CC32 \(latest.selection.bankLSB)  ·  PC \(latest.selection.program)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 220, alignment: .leading)

                TextField("Nome mostrado no PA700", text: nameBinding(for: latest))
                    .font(.title3.weight(.medium))
                    .focused($quickNameID, equals: latest.id)
                    .onSubmit {
                        model.commitBatchSoundName(id: latest.id)
                        quickNameID = nil
                    }

                Label(
                    latest.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Nome pendente" : "Nome salvo",
                    systemImage: latest.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "pencil" : "checkmark.circle.fill"
                )
                .foregroundStyle(latest.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? LabTheme.draft : LabTheme.verified)
            }
        }
    }

    private var catalogHeader: some View {
        HStack {
            Text("Catálogo").font(.headline)
            Picker("Biblioteca", selection: $libraryFilter) {
                ForEach(LibraryFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 390)
            Spacer()
            Text("\(displayEntries.count) exibidos")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if model.batchPendingNameCount == 0, !model.batchSoundEntries.isEmpty {
                Label("Todos nomeados", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(LabTheme.verified)
            } else if model.batchPendingNameCount > 0 {
                Label("\(model.batchPendingNameCount) nomes pendentes", systemImage: "pencil.circle")
                    .foregroundStyle(LabTheme.draft)
            }
        }
    }

    @ViewBuilder
    private var catalog: some View {
        if model.batchSoundEntries.isEmpty {
            ContentUnavailableView {
                Label("Pronto para mapear", systemImage: "pianokeys")
            } description: {
                Text("Comece uma tela e toque os timbres visíveis no PA700. Todos permanecem Draft até verificação.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayEntries.isEmpty, libraryFilter == .user {
            ContentUnavailableView {
                Label("Nenhum som User capturado", systemImage: "person.crop.square")
            } description: {
                Text("Se a aba User do PA700 também estiver vazia, o catálogo está completo. Se houver sons, capture apenas essas páginas.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(displayEntries) {
                TableColumn("#") { entry in
                    Text(String((model.batchSoundEntries.firstIndex(where: { $0.id == entry.id }) ?? 0) + 1))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(36)

                TableColumn("Nome no PA700") { entry in
                    TextField("Nome pendente", text: nameBinding(for: entry))
                        .textFieldStyle(.plain)
                        .onSubmit { model.commitBatchSoundName(id: entry.id) }
                }
                .width(min: 210, ideal: 280)

                TableColumn("Biblioteca") { entry in
                    Text(entry.library ?? "User")
                        .foregroundStyle(.secondary)
                }
                .width(80)
                TableColumn("Categoria") { entry in
                    Text(entry.category ?? "—")
                        .foregroundStyle(.secondary)
                }
                .width(min: 85, ideal: 120)
                TableColumn("CC0") { entry in Text(String(entry.selection.bankMSB)).monospacedDigit() }.width(55)
                TableColumn("CC32") { entry in Text(String(entry.selection.bankLSB)).monospacedDigit() }.width(55)
                TableColumn("PC") { entry in Text(String(entry.selection.program)).monospacedDigit() }.width(55)
                TableColumn("Vezes") { entry in Text(String(entry.occurrenceCount)).monospacedDigit() }.width(55)
                TableColumn("Estado") { entry in
                    let sampled = entry.verificationBasis == .catalogSampling
                    Text(entry.status == .verified ? (sampled ? "Amostral" : "Verified") : "Draft")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(entry.status == .verified ? LabTheme.verified : LabTheme.draft)
                }
                .width(72)
            }
            .frame(minHeight: 180)

            if let url = model.batchCatalogURL {
                Text("Salvamento automático: \(url.path)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }

    private var arrow: some View {
        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 6) {
            Text(String(number))
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(LabTheme.signal.opacity(0.14), in: Circle())
                .foregroundStyle(LabTheme.signal)
            Text(text)
        }
    }

    private func selectScreen(_ id: UUID) {
        selectedScreenID = id
        loadNames(for: id)
    }

    private func loadNames(for screenID: UUID) {
        let entries = model.batchEntries(for: screenID)
        let existing = entries.map { $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
        bulkNames = existing.allSatisfy(\.isEmpty) ? "" : existing.joined(separator: "\n")
    }

    private func nameBinding(for entry: BatchSoundEntry) -> Binding<String> {
        Binding(
            get: { model.batchSoundEntries.first(where: { $0.id == entry.id })?.displayName ?? "" },
            set: { model.renameBatchSound(id: entry.id, displayName: $0) }
        )
    }
}
