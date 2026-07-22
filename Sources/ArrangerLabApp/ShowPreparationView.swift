import ArrangerLabCore
import SwiftUI
import UniformTypeIdentifiers

private enum ShowSoundLibraryFilter: String, CaseIterable, Identifiable {
    case user = "User"
    case factory = "Factory"
    case legacy = "Legacy"
    case gmxg = "GM/XG"
    case all = "Todos"

    var id: String { rawValue }
}

struct ShowPreparationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ConnectionStrip()
            Divider()
            TabView {
                ShowPresetEditor()
                    .tabItem { Label("Músicas e presets", systemImage: "music.note") }
                ShowSetListEditor()
                    .tabItem { Label("Repertórios", systemImage: "music.note.list") }
            }
            .padding(LabTheme.standard)
        }
        .tint(LabTheme.signal)
        .alert("Arranger Lab", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

private struct ShowPresetEditor: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedPresetID: UUID?
    @State private var draft = ShowPresetEditor.newDraft()
    @State private var chartEditorText = ""
    @State private var chartTransposeSteps = 0
    @State private var isPDFImporterPresented = false
    @State private var isImportingPDF = false
    @State private var presetPendingDeletion: ShowPreset?
    @State private var confirmsChartRestore = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("MÚSICAS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.showPresets.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)

                Divider()

                List(model.showPresets, selection: $selectedPresetID) { preset in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preset.songTitle)
                            .fontWeight(.medium)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Text(preset.hasDirectSetup ? "JPD · Kbd \(preset.keyboardSetSlot ?? 0)" : songBookLabel(preset.songBookNumber))
                            Text("·")
                            Text(preset.isReadyToPlay ? "Configurada" : "Somente leitura")
                                .foregroundStyle(preset.isReadyToPlay ? LabTheme.verified : LabTheme.draft)
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(Optional(preset.id))
                }

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Button("Importar PDF(s)", systemImage: "doc.badge.plus") {
                        isPDFImporterPresented = true
                    }
                    .disabled(isImportingPDF)
                    Button("Novo preset", systemImage: "plus") { beginNewPreset() }
                    Button("Reimportar Showboat Jul 23", systemImage: "arrow.clockwise") {
                        if model.importShowboatJul23Catalog() {
                            selectFirstPreset(in: "showboat-jul-23-gojam")
                        }
                    }
                    .help("Restaura as 26 músicas do goJam sem apagar tons, transposes ou letras editadas")
                    Button("Reimportar Boteco Jul3", systemImage: "arrow.clockwise") {
                        if model.importBundledShowCatalog() {
                            selectFirstPreset(in: "boteco-jul3-gojam")
                        }
                    }
                    .help("Restaura músicas ausentes sem apagar suas edições")
                }
                .buttonStyle(.borderless)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 270)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: LabTheme.section) {
                        PageHeader(
                            title: selectedPresetID == nil ? "Novo preset" : draft.songTitle,
                            subtitle: "Prepare a cifra e a configuração enviada diretamente ao PA700. SongBook é opcional."
                        )

                        songAndSongBookSection
                        partsSection
                        effectsSection
                        chartSection

                        Label(model.showStatus, systemImage: statusIcon)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 940, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(LabTheme.page)
                }

                Divider()

                actionBar
                    .padding(.horizontal, LabTheme.page)
                    .frame(height: 58)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .onAppear { selectFirstPreset() }
        .onChange(of: selectedPresetID) { _, _ in loadSelectedPreset() }
        .fileImporter(
            isPresented: $isPDFImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            importSelectedPDFs(result)
        }
        .confirmationDialog(
            "Excluir preset?",
            isPresented: Binding(get: { presetPendingDeletion != nil }, set: { if !$0 { presetPendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Excluir definitivamente", role: .destructive) {
                guard let presetPendingDeletion else { return }
                model.deleteShowPreset(presetPendingDeletion)
                beginNewPreset()
                self.presetPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) { presetPendingDeletion = nil }
        } message: {
            Text("A música também será removida dos repertórios. As cenas antigas do Laboratório não serão alteradas.")
        }
        .confirmationDialog(
            "Restaurar a cifra original?",
            isPresented: $confirmsChartRestore,
            titleVisibility: .visible
        ) {
            Button("Restaurar conteúdo extraído", role: .destructive) { restoreOriginalChart() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("A edição atual será substituída no formulário. A mudança só será gravada quando você salvar o preset.")
        }
    }

    private var songAndSongBookSection: some View {
        GroupBox("Música e execução") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 13) {
                GridRow {
                    Text("Música")
                    TextField("Nome da música", text: $draft.songTitle)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Tom da cifra")
                    HStack(spacing: 10) {
                        TextField("Ex.: G, F#m", text: $draft.originalKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        if let source = draft.source {
                            Label(pageLabel(source), systemImage: "doc.richtext")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                GridRow {
                    Text("SongBook (opcional)")
                    HStack(spacing: 10) {
                        TextField("Ainda não definido", text: songBookBinding)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                        Text("0 a 9999. Deixe vazio enquanto a música estiver em preparação.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("Transpose")
                    HStack(spacing: 10) {
                        Text(transposeText(draft.transposeSemitones))
                            .font(.body.monospacedDigit())
                            .frame(width: 100, alignment: .leading)
                        Stepper("Transpose", value: $draft.transposeSemitones, in: -12...12)
                            .labelsHidden()
                        Text(draft.hasDirectSetup ? "Enviado diretamente pelo Mac ao PA700." : "Use SongBook como alternativa.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
        }
    }

    private var partsSection: some View {
        GroupBox("Upper e Lower") {
            VStack(spacing: 0) {
                ForEach($draft.parts) { $part in
                    ShowPartSoundRow(part: $part, entries: model.batchSoundEntries)
                    .padding(.vertical, 8)
                    if part.part != .lower { Divider() }
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private var effectsSection: some View {
        GroupBox("Efeitos e notas") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Efeitos") {
                    TextField("Ex.: reverb curto, rotary lento", text: $draft.effectsSummary, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }
                LabeledContent("Notas") {
                    TextField("Lembretes para a execução", text: $draft.notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                }
            }
            .padding(10)
        }
    }

    private var chartSection: some View {
        GroupBox("Cifra e letra") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Toggle("Cifras visíveis por padrão", isOn: $draft.readerSettings.showChords)
                    Spacer()
                    Button("Restaurar original", systemImage: "arrow.uturn.backward") {
                        confirmsChartRestore = true
                    }
                    .disabled(model.originalShowChart(for: draft) == nil)
                }

                HStack(spacing: 12) {
                    Text("Transpor a cifra")
                        .font(.callout.weight(.medium))
                    Text(transposeText(chartTransposeSteps))
                        .font(.callout.monospacedDigit())
                        .frame(width: 94, alignment: .leading)
                    Stepper("Semitons da cifra", value: $chartTransposeSteps, in: -11...11)
                        .labelsHidden()
                    if let targetKey = ShowMusicTheory.transposedKey(draft.originalKey, by: chartTransposeSteps) {
                        Text("\(draft.originalKey) → \(targetKey)")
                            .font(.callout.monospaced().weight(.semibold))
                            .foregroundStyle(LabTheme.signal)
                    }
                    Button("Aplicar à cifra", systemImage: "arrow.left.arrow.right") { transposeChart() }
                        .disabled(chartTransposeSteps == 0 || ShowMusicTheory.transposedKey(draft.originalKey, by: chartTransposeSteps) == nil)
                    Spacer()
                }

                Text("Use # no início de uma seção e > no início de uma linha de acordes. Linhas sem prefixo são letra. O PDF de origem não é armazenado.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $chartEditorText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: LabTheme.radius))
                    .overlay {
                        RoundedRectangle(cornerRadius: LabTheme.radius)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    }
                    .frame(minHeight: 480)
                    .accessibilityLabel("Editor de cifra e letra")

                HStack(spacing: 12) {
                    Text("Tamanho inicial no Show")
                        .font(.callout)
                    Slider(value: $draft.readerSettings.fontScale, in: 0.75...2, step: 0.05)
                        .frame(width: 220)
                    Text("\(Int(draft.readerSettings.fontScale * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 42, alignment: .trailing)
                }
            }
            .padding(10)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("Salvar rascunho", systemImage: "square.and.arrow.down") { saveDraft() }
                .buttonStyle(.borderedProminent)

            Button("Salvar e testar no PA700", systemImage: "play.fill") { saveAndTest() }
                .disabled(!model.connected || (!draft.hasDirectSetup && draft.songBookNumber == nil))

            if let savedPreset, model.pendingShowConfirmationID == savedPreset.id {
                Button("Confirmar no PA700", systemImage: "checkmark.seal.fill") {
                    if model.confirmShowPreset(savedPreset) { loadSelectedPreset() }
                }
                .buttonStyle(.borderedProminent)
                .tint(LabTheme.verified)
            }

            Spacer()

            if let savedPreset {
                Button("Excluir", systemImage: "trash", role: .destructive) {
                    presetPendingDeletion = savedPreset
                }
            }
        }
    }

    private var savedPreset: ShowPreset? {
        guard let selectedPresetID else { return nil }
        return model.showPresets.first { $0.id == selectedPresetID }
    }

    private var statusIcon: String {
        savedPreset?.isReadyToPlay == true ? "checkmark.seal.fill" : "info.circle"
    }

    private var songBookBinding: Binding<String> {
        Binding(
            get: { draft.songBookNumber.map(String.init) ?? "" },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                draft.songBookNumber = digits.isEmpty ? nil : Int(digits)
            }
        )
    }

    private func saveDraft() {
        syncChartToDraft()
        if model.saveShowPreset(draft) {
            selectedPresetID = draft.id
            loadSelectedPreset()
        }
    }

    private func saveAndTest() {
        syncChartToDraft()
        guard model.saveShowPreset(draft),
              let preset = model.showPresets.first(where: { $0.id == draft.id }) else { return }
        selectedPresetID = preset.id
        draft = preset
        chartEditorText = ShowChartLine.editorText(from: preset.chartLines)
        model.testShowPreset(preset)
    }

    private func beginNewPreset() {
        selectedPresetID = nil
        draft = Self.newDraft()
        chartEditorText = ""
        chartTransposeSteps = 0
    }

    private func selectFirstPreset() {
        guard selectedPresetID == nil, let first = model.showPresets.first else { return }
        selectedPresetID = first.id
        loadSelectedPreset()
    }

    private func selectFirstPreset(in catalogID: String) {
        guard let first = model.showPresets.first(where: { $0.source?.catalogID == catalogID }) else { return }
        selectedPresetID = first.id
        loadSelectedPreset()
    }

    private func loadSelectedPreset() {
        guard let selectedPresetID,
              let preset = model.showPresets.first(where: { $0.id == selectedPresetID }) else { return }
        draft = preset
        chartEditorText = ShowChartLine.editorText(from: preset.chartLines)
        chartTransposeSteps = 0
    }

    private func restoreOriginalChart() {
        guard let original = model.originalShowChart(for: draft) else { return }
        draft.chartLines = original
        chartEditorText = ShowChartLine.editorText(from: original)
        chartTransposeSteps = 0
    }

    private func transposeChart() {
        guard chartTransposeSteps != 0,
              let targetKey = ShowMusicTheory.transposedKey(draft.originalKey, by: chartTransposeSteps) else { return }
        syncChartToDraft()
        draft.chartLines = ShowMusicTheory.transposeChart(
            draft.chartLines,
            by: chartTransposeSteps,
            preferFlats: targetKey.contains("b")
        )
        draft.originalKey = targetKey
        chartEditorText = ShowChartLine.editorText(from: draft.chartLines)
        chartTransposeSteps = 0
    }

    private func importSelectedPDFs(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else {
            if case let .failure(error) = result { model.lastError = error.localizedDescription }
            return
        }
        isImportingPDF = true
        Task { @MainActor in
            var extracted: [ShowPreset] = []
            var failures: [String] = []
            for url in urls {
                do {
                    extracted.append(try ShowPDFImporter.extractPreset(from: url))
                } catch {
                    failures.append(error.localizedDescription)
                }
                await Task.yield()
            }
            let importedIDs = model.importExtractedShowPresets(extracted)
            if let firstID = importedIDs.first {
                selectedPresetID = firstID
                loadSelectedPreset()
            }
            if !failures.isEmpty {
                model.lastError = failures.joined(separator: "\n")
            }
            isImportingPDF = false
        }
    }

    private func syncChartToDraft() {
        draft.chartLines = ShowChartLine.parseEditorText(chartEditorText)
    }

    private static func newDraft() -> ShowPreset {
        ShowPreset(songTitle: "")
    }

    private func pageLabel(_ source: ShowPresetSource) -> String {
        if source.sourceURL != nil {
            return "Importado de \(source.documentName); cifra e letra salvas localmente"
        }
        let count = max(1, source.endPage - source.startPage + 1)
        return "Extraído de \(source.documentName) (\(count) \(count == 1 ? "página" : "páginas")); arquivo não armazenado"
    }

    private func songBookLabel(_ number: Int?) -> String {
        number.map { "SongBook \($0)" } ?? "Sem SongBook"
    }

    private func transposeText(_ value: Int) -> String {
        value == 0 ? "0 semitons" : "\(value > 0 ? "+" : "")\(value) semitons"
    }
}

private struct ShowPartSoundRow: View {
    @Binding var part: ShowPresetPart
    let entries: [BatchSoundEntry]
    @State private var isBrowserPresented = false

    private var selectedEntry: BatchSoundEntry? {
        guard let soundID = part.soundID else { return nil }
        return entries.first { $0.id == soundID }
    }

    private var hasSavedName: Bool {
        let value = part.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value != "Não informado" && value != "Desligado"
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle(part.part.rawValue, isOn: enabledBinding)
                .toggleStyle(.checkbox)
                .frame(width: 105, alignment: .leading)

            Button {
                isBrowserPresented = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: part.isEnabled ? "pianokeys" : "speaker.slash")
                        .foregroundStyle(part.isEnabled ? LabTheme.signal : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasSavedName ? part.displayName : (part.isEnabled ? "Escolher timbre" : "Parte desligada"))
                            .fontWeight(hasSavedName ? .medium : .regular)
                            .foregroundStyle(hasSavedName ? Color.primary : Color.secondary)
                        Text(selectionDetail)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 11)
            .frame(minHeight: 44)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: LabTheme.radius))
            .overlay {
                RoundedRectangle(cornerRadius: LabTheme.radius)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            }
            .disabled(!part.isEnabled)
            .popover(isPresented: $isBrowserPresented, arrowEdge: .trailing) {
                ShowSoundBrowser(
                    partName: part.part.rawValue,
                    entries: entries,
                    selectedSoundID: part.soundID
                ) { entry in
                    part.displayName = entry.effectiveName
                    part.soundID = entry.id
                    part.soundLibrary = ShowSoundBrowser.libraryName(for: entry)
                    part.isEnabled = true
                    isBrowserPresented = false
                }
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { part.isEnabled },
            set: { enabled in
                part.isEnabled = enabled
                if enabled && !hasSavedName {
                    part.displayName = ""
                    part.soundID = nil
                    part.soundLibrary = nil
                }
            }
        )
    }

    private var selectionDetail: String {
        if let selectedEntry {
            return "\(ShowSoundBrowser.libraryName(for: selectedEntry)) · \(selectedEntry.selection.display)"
        }
        if hasSavedName {
            return "\(part.soundLibrary ?? "Nome salvo") · vincule ao catálogo"
        }
        return part.isEnabled ? "User, Factory, Legacy ou GM/XG" : "A escolha fica preservada"
    }
}

private struct ShowSoundBrowser: View {
    let partName: String
    let entries: [BatchSoundEntry]
    let selectedSoundID: String?
    let onSelect: (BatchSoundEntry) -> Void

    @State private var searchText = ""
    @State private var libraryFilter: ShowSoundLibraryFilter = .user
    @State private var categoryFilter = "Todas"

    private var libraryEntries: [BatchSoundEntry] {
        entries.filter { entry in
            libraryFilter == .all || Self.libraryName(for: entry) == libraryFilter.rawValue
        }
    }

    private var categories: [String] {
        ["Todas"] + Set(libraryEntries.compactMap(\.category)).sorted()
    }

    private var filteredEntries: [BatchSoundEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return libraryEntries.filter { entry in
            let categoryMatches = categoryFilter == "Todas" || entry.category == categoryFilter
            let searchMatches = query.isEmpty
                || entry.effectiveName.localizedCaseInsensitiveContains(query)
                || entry.selection.display.localizedCaseInsensitiveContains(query)
                || (entry.category?.localizedCaseInsensitiveContains(query) ?? false)
            return categoryMatches && searchMatches
        }
        .sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return $0.effectiveName.localizedStandardCompare($1.effectiveName) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Timbre para \(partName)")
                    .font(.title3.weight(.semibold))
                Text("User abre primeiro porque reúne os sons personalizados já capturados.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Biblioteca", selection: $libraryFilter) {
                ForEach(ShowSoundLibraryFilter.allCases) { library in
                    Text("\(library.rawValue) \(libraryCount(library))").tag(library)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: libraryFilter) { _, _ in categoryFilter = "Todas" }

            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Buscar nome, categoria ou endereço", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: LabTheme.radius))

                Picker("Categoria", selection: $categoryFilter) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 150)
            }

            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    libraryFilter == .user ? "Nenhum timbre User encontrado" : "Nenhum timbre encontrado",
                    systemImage: "pianokeys",
                    description: Text(libraryFilter == .user
                        ? "Capture ou nomeie os bancos User no Laboratório para eles aparecerem aqui."
                        : "Tente outro nome, categoria ou biblioteca.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredEntries) { entry in
                    Button { onSelect(entry) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(entry.effectiveName)
                                        .fontWeight(entry.id == selectedSoundID ? .semibold : .regular)
                                    if entry.isFavorite {
                                        Image(systemName: "star.fill")
                                            .font(.caption)
                                            .foregroundStyle(.yellow)
                                    }
                                }
                                Text("\(Self.libraryName(for: entry)) · \(entry.category ?? "Sem categoria") · \(entry.selection.display)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entry.id == selectedSoundID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(LabTheme.verified)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
            }

            HStack {
                Text("\(filteredEntries.count) timbres")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Referência do preset; o estado real continua vindo do SongBook.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 650, height: 540)
    }

    static func libraryName(for entry: BatchSoundEntry) -> String {
        if entry.selection.bankMSB == 121, (64...67).contains(entry.selection.bankLSB) {
            return ShowSoundLibraryFilter.user.rawValue
        }
        return entry.library ?? "Outros"
    }

    private func libraryCount(_ library: ShowSoundLibraryFilter) -> Int {
        if library == .all { return entries.count }
        return entries.lazy.filter { Self.libraryName(for: $0) == library.rawValue }.count
    }
}

private struct ShowSetListEditor: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedSetListID: UUID?
    @State private var newSetListName = ""
    @State private var editingName = ""
    @State private var setListPendingDeletion: ShowSetList?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(model.showSetLists, selection: $selectedSetListID) { setList in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(setList.name).fontWeight(.medium)
                        HStack(spacing: 6) {
                            Text("\(setList.items.count) músicas")
                            if model.activeShowSetListID == setList.id {
                                Text("No Show").foregroundStyle(LabTheme.verified)
                            }
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(Optional(setList.id))
                }

                Divider()

                VStack(spacing: 8) {
                    TextField("Novo repertório", text: $newSetListName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { createSetList() }
                    Button("Criar repertório", systemImage: "plus") { createSetList() }
                        .disabled(newSetListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let setList = selectedSetList {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        TextField("Nome do repertório", text: $editingName)
                            .font(.title2.weight(.semibold))
                            .textFieldStyle(.plain)
                            .onSubmit { model.renameShowSetList(setList, to: editingName) }
                        Button("Salvar nome") { model.renameShowSetList(setList, to: editingName) }
                        Spacer()
                        if model.activeShowSetListID == setList.id {
                            Label("Repertório do Show", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(LabTheme.verified)
                        } else {
                            Button("Usar no Show", systemImage: "play.rectangle.fill") {
                                model.selectShowSetList(setList.id)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    HStack {
                        Menu("Adicionar música", systemImage: "text.badge.plus") {
                            ForEach(model.showPresets) { preset in
                                Button {
                                    model.addShowPreset(preset, to: setList)
                                } label: {
                                    Text("\(preset.songTitle)\(preset.isConfirmed ? "" : " · Rascunho")")
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Text("Músicas podem se repetir no repertório.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Excluir repertório", systemImage: "trash", role: .destructive) {
                            setListPendingDeletion = setList
                        }
                    }

                    if setList.items.isEmpty {
                        ContentUnavailableView(
                            "Adicione músicas na ordem do show",
                            systemImage: "music.note.list",
                            description: Text("Rascunhos entram na lista, mas ficam bloqueados no palco até a confirmação no PA700.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(Array(setList.items.enumerated()), id: \.element.id) { index, item in
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, alignment: .trailing)
                                    if let preset = model.showPreset(for: item) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(preset.songTitle).fontWeight(.medium)
                                            HStack(spacing: 5) {
                                                Text(preset.songBookNumber.map { "SongBook \($0)" } ?? "Sem SongBook")
                                                Text("·")
                                                Text(preset.isConfirmed ? "Confirmado" : "Rascunho")
                                                    .foregroundStyle(preset.isConfirmed ? Color.secondary : LabTheme.draft)
                                            }
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        }
                                    } else {
                                        Text("Preset indisponível").foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button { model.moveShowSetListItem(item, in: setList, offset: -1) } label: {
                                        Image(systemName: "chevron.up")
                                    }
                                    .disabled(index == 0)
                                    .help("Mover para cima")
                                    Button { model.moveShowSetListItem(item, in: setList, offset: 1) } label: {
                                        Image(systemName: "chevron.down")
                                    }
                                    .disabled(index == setList.items.count - 1)
                                    .help("Mover para baixo")
                                    Button { model.removeShowSetListItem(item, from: setList) } label: {
                                        Image(systemName: "xmark")
                                    }
                                    .help("Remover do repertório")
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .listStyle(.inset)
                    }

                    Label(model.showStatus, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(
                    "Crie um repertório",
                    systemImage: "music.note.list",
                    description: Text("Depois adicione os presets na ordem da apresentação.")
                )
            }
        }
        .onAppear {
            selectedSetListID = model.activeShowSetListID ?? model.showSetLists.first?.id
            loadSetListName()
        }
        .onChange(of: selectedSetListID) { _, _ in loadSetListName() }
        .confirmationDialog(
            "Excluir repertório?",
            isPresented: Binding(get: { setListPendingDeletion != nil }, set: { if !$0 { setListPendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Excluir definitivamente", role: .destructive) {
                guard let setListPendingDeletion else { return }
                model.deleteShowSetList(setListPendingDeletion)
                selectedSetListID = model.activeShowSetListID ?? model.showSetLists.first?.id
                self.setListPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) { setListPendingDeletion = nil }
        } message: {
            Text("Os presets continuarão salvos e poderão ser usados em outro repertório.")
        }
    }

    private var selectedSetList: ShowSetList? {
        guard let selectedSetListID else { return nil }
        return model.showSetLists.first { $0.id == selectedSetListID }
    }

    private func createSetList() {
        let name = newSetListName
        if model.createShowSetList(named: name),
           let created = model.showSetLists.first(where: {
               $0.name.localizedCaseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
           }) {
            selectedSetListID = created.id
            newSetListName = ""
            loadSetListName()
        }
    }

    private func loadSetListName() {
        editingName = selectedSetList?.name ?? ""
    }
}
