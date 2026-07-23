import ArrangerLabCore
import SwiftUI
import UniformTypeIdentifiers

enum ShowWorkspaceMode: String, CaseIterable, Identifiable {
    case show = "Show"
    case repertoire = "Repertório"

    var id: String { rawValue }
}

struct ShowRepertoireWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isLibraryPresented: Bool
    let onEditMusicFromOrder: (ShowPreset) -> Void
    let onEditMusicFromLibrary: (ShowPreset) -> Void
    let onNewMusicFromLibrary: () -> Void
    let onSelectRepertoire: (UUID?) -> Void
    let onStartShow: (UUID) -> Void

    @State private var selectedSetListID: UUID?
    @State private var catalogSearch = ""
    @State private var librarySourceSetListID: UUID?
    @State private var nameDraft = ""
    @State private var newSetListName = ""
    @State private var isCreatingSetList = false
    @State private var setListPendingDeletion: ShowSetList?
    @State private var isPDFImporterPresented = false
    @State private var isImportingPDF = false
    @FocusState private var addMusicButtonFocused: Bool
    @FocusState private var librarySearchFocused: Bool

    private var selectedSetList: ShowSetList? {
        guard let selectedSetListID else { return nil }
        return model.showSetLists.first { $0.id == selectedSetListID }
    }

    private var occurrenceCounts: [UUID: Int] {
        Dictionary(grouping: selectedSetList?.items ?? [], by: \.presetID).mapValues(\.count)
    }

    private var librarySourcePresetIDs: Set<UUID>? {
        guard let librarySourceSetListID,
              let source = model.showSetLists.first(where: { $0.id == librarySourceSetListID }) else { return nil }
        return Set(source.items.map(\.presetID))
    }

    private var filteredCatalog: [ShowPreset] {
        let query = catalogSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.showPresets.filter { preset in
            let searchMatches = query.isEmpty || preset.songTitle.localizedCaseInsensitiveContains(query)
            let sourceMatches = librarySourcePresetIDs?.contains(preset.id) ?? true
            return searchMatches && sourceMatches
        }
        .sorted { $0.songTitle.localizedStandardCompare($1.songTitle) == .orderedAscending }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                HStack(spacing: 0) {
                    repertoireColumn
                        .frame(width: min(260, max(210, geometry.size.width * 0.2)))
                    Divider()
                    orderColumn
                        .frame(minWidth: 350, maxWidth: .infinity)
                }

                if isLibraryPresented {
                    HStack(spacing: 0) {
                        Divider()
                        libraryPanel
                            .frame(width: 420)
                    }
                    .background(LabTheme.stageBackground)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isLibraryPresented)
        .background(LabTheme.stageBackground)
        .onAppear {
            selectedSetListID = model.activeShowSetListID ?? model.showSetLists.first?.id
            loadSelectedName()
        }
        .onChange(of: model.activeShowSetListID) { _, value in
            selectedSetListID = value
            loadSelectedName()
        }
        .onChange(of: model.showSetLists) { _, setLists in
            if selectedSetListID.flatMap({ id in setLists.first(where: { $0.id == id }) }) == nil {
                onSelectRepertoire(model.activeShowSetListID ?? setLists.first?.id)
            }
            if let librarySourceSetListID,
               !setLists.contains(where: { $0.id == librarySourceSetListID }) {
                self.librarySourceSetListID = nil
            }
        }
        .alert("Novo repertório", isPresented: $isCreatingSetList) {
            TextField("Nome do repertório", text: $newSetListName)
            Button("Criar") {
                if model.createShowSetList(named: newSetListName),
                   let created = model.showSetLists.first(where: { $0.name == newSetListName.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                    onSelectRepertoire(created.id)
                }
                newSetListName = ""
            }
            Button("Cancelar", role: .cancel) { newSetListName = "" }
        }
        .confirmationDialog(
            "Excluir o repertório \(setListPendingDeletion?.name ?? "")?",
            isPresented: Binding(get: { setListPendingDeletion != nil }, set: { if !$0 { setListPendingDeletion = nil } })
        ) {
            Button("Excluir repertório", role: .destructive) {
                if let setListPendingDeletion { model.deleteShowSetList(setListPendingDeletion) }
                setListPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) { setListPendingDeletion = nil }
        } message: {
            Text("As músicas continuam na biblioteca.")
        }
        .fileImporter(
            isPresented: $isPDFImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true,
            onCompletion: importSelectedPDFs
        )
    }

    private var repertoireColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("REPERTÓRIOS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("\(model.showSetLists.count) salvos")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Novo repertório", systemImage: "plus") { isCreatingSetList = true }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Criar repertório")
            }
            .padding(16)

            Divider()

            if model.showSetLists.isEmpty {
                ContentUnavailableView("Nenhum repertório", systemImage: "music.note.list", description: Text("Crie um repertório para montar a ordem do show."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.showSetLists, selection: Binding(
                    get: { selectedSetListID },
                    set: onSelectRepertoire
                )) { setList in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(setList.name).fontWeight(.medium).lineLimit(2)
                        Text("\(setList.items.count) músicas")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .tag(Optional(setList.id))
                    .accessibilityLabel("\(setList.name), \(setList.items.count) músicas")
                }
                .listStyle(.sidebar)
            }
        }
        .background(LabTheme.stageSurface.opacity(0.72))
    }

    private var orderColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let setList = selectedSetList {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        TextField("Nome do repertório", text: $nameDraft)
                            .font(.title2.weight(.semibold))
                            .textFieldStyle(.plain)
                            .onSubmit { rename(setList) }
                            .accessibilityLabel("Nome do repertório")
                        Button("Salvar nome", systemImage: "checkmark") { rename(setList) }
                            .labelStyle(.iconOnly)
                            .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) == setList.name)
                        Button(
                            isLibraryPresented ? "Fechar biblioteca" : "Adicionar músicas",
                            systemImage: isLibraryPresented ? "sidebar.right" : "plus"
                        ) {
                            toggleLibrary()
                        }
                        .focused($addMusicButtonFocused)
                        .accessibilityHint(isLibraryPresented ? "Fecha a biblioteca" : "Abre a biblioteca de músicas")
                        Button("Iniciar show", systemImage: "play.fill") { onStartShow(setList.id) }
                            .buttonStyle(.borderedProminent)
                            .disabled(setList.items.isEmpty)
                        Menu {
                            Button("Excluir repertório", systemImage: "trash", role: .destructive) {
                                setListPendingDeletion = setList
                            }
                        } label: {
                            Label("Mais ações", systemImage: "ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    Text("Arraste para ordenar ou use os botões de subir e descer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(18)

                Divider()

                if setList.items.isEmpty {
                    ContentUnavailableView(
                        label: { Label("Repertório vazio", systemImage: "text.badge.plus") },
                        description: { Text("Adicione músicas para montar a ordem do show.") },
                        actions: {
                            Button("Adicionar músicas", systemImage: "plus") { openLibrary() }
                                .buttonStyle(.borderedProminent)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(setList.items.enumerated()), id: \.element.id) { index, item in
                            orderRow(index: index, item: item, setList: setList)
                        }
                        .onMove { offsets, destination in
                            model.moveShowSetListItems(in: setList, fromOffsets: offsets, toOffset: destination)
                        }
                    }
                    .listStyle(.inset)
                }
            } else {
                ContentUnavailableView("Selecione um repertório", systemImage: "sidebar.left")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func orderRow(index: Int, item: ShowSetListItem, setList: ShowSetList) -> some View {
        let preset = model.showPreset(for: item)
        return HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(String(format: "%02d", index + 1))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(preset?.songTitle ?? "Música indisponível")
                    .fontWeight(.medium)
                Text(musicSetupLabel(preset))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(preset?.isReadyToPlay == true ? LabTheme.verified : LabTheme.draft)
            }
            Spacer()
            Button("Editar \(preset?.songTitle ?? "música")", systemImage: "pencil") {
                if let preset {
                    isLibraryPresented = false
                    onEditMusicFromOrder(preset)
                }
            }
            .labelStyle(.iconOnly)
            .disabled(preset == nil)
            Button("Subir", systemImage: "chevron.up") { model.moveShowSetListItem(item, in: setList, offset: -1) }
                .labelStyle(.iconOnly)
                .disabled(index == 0)
            Button("Descer", systemImage: "chevron.down") { model.moveShowSetListItem(item, in: setList, offset: 1) }
                .labelStyle(.iconOnly)
                .disabled(index == setList.items.count - 1)
            Button("Remover", systemImage: "minus.circle") { model.removeShowSetListItem(item, from: setList) }
                .labelStyle(.iconOnly)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }

    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Adicionar músicas")
                            .font(.title3.weight(.semibold))
                        Text("\(filteredCatalog.count) de \(model.showPresets.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Importar PDF", systemImage: "doc.badge.plus") { isPDFImporterPresented = true }
                        .labelStyle(.iconOnly)
                        .disabled(isImportingPDF)
                    Button("Nova música", systemImage: "plus") { onNewMusicFromLibrary() }
                        .labelStyle(.iconOnly)
                    Menu {
                        Button("Reimportar Showboat Jul 23", systemImage: "arrow.clockwise") { _ = model.importShowboatJul23Catalog() }
                        Button("Reimportar Boteco Jul3", systemImage: "arrow.clockwise") { _ = model.importBundledShowCatalog() }
                    } label: {
                        Label("Mais ações da biblioteca", systemImage: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Button("Fechar biblioteca", systemImage: "xmark") { closeLibrary() }
                        .labelStyle(.iconOnly)
                }

                Text("Adicionar a: \(selectedSetList?.name ?? "Nenhum repertório")")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LabTheme.signal)

                TextField("Buscar música", text: $catalogSearch)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Buscar na biblioteca de músicas")
                    .focused($librarySearchFocused)

                LabeledContent("Mostrar") {
                    Picker("Mostrar músicas", selection: $librarySourceSetListID) {
                        Text("Todas as músicas").tag(Optional<UUID>.none)
                        ForEach(model.showSetLists) { setList in
                            Text(setList.name).tag(Optional(setList.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(16)

            Divider()

            if filteredCatalog.isEmpty {
                ContentUnavailableView("Nenhuma música", systemImage: "magnifyingglass", description: Text("Ajuste a busca ou escolha outro repertório."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredCatalog) { preset in
                    catalogRow(preset)
                }
                .listStyle(.inset)
            }
        }
        .background(LabTheme.stageSurface.opacity(0.48))
        .onExitCommand { closeLibrary() }
    }

    private func catalogRow(_ preset: ShowPreset) -> some View {
        let count = occurrenceCounts[preset.id, default: 0]
        return HStack(spacing: 10) {
            Button { onEditMusicFromLibrary(preset) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.songTitle).fontWeight(.medium).lineLimit(2)
                    HStack(spacing: 6) {
                        Text(musicSetupLabel(preset))
                        if count > 0 {
                            Label("\(count)x", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(LabTheme.verified)
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("Adicionar \(preset.songTitle)", systemImage: "plus") {
                if let selectedSetList { model.addShowPreset(preset, to: selectedSetList) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderedProminent)
            .disabled(selectedSetList == nil)
            .help(count == 0 ? "Adicionar ao repertório" : "Adicionar outra ocorrência")
        }
        .padding(.vertical, 4)
    }

    private func toggleLibrary() {
        if isLibraryPresented {
            closeLibrary()
        } else {
            openLibrary()
        }
    }

    private func openLibrary() {
        librarySourceSetListID = nil
        catalogSearch = ""
        isLibraryPresented = true
        Task { @MainActor in
            await Task.yield()
            librarySearchFocused = true
        }
    }

    private func closeLibrary() {
        isLibraryPresented = false
        addMusicButtonFocused = true
    }

    private func rename(_ setList: ShowSetList) {
        model.renameShowSetList(setList, to: nameDraft)
        loadSelectedName()
    }

    private func loadSelectedName() {
        nameDraft = selectedSetList?.name ?? ""
    }

    private func musicSetupLabel(_ preset: ShowPreset?) -> String {
        guard let preset else { return "Indisponível" }
        if preset.hasDirectSetup {
            let name = preset.arrangerStyleID.flatMap { id in model.arrangerStyles.first { $0.id == id }?.displayName } ?? "Style"
            return "\(name) · Kbd \(preset.keyboardSetSlot ?? 1)"
        }
        return preset.songBookNumber.map { "SongBook \($0)" } ?? "Somente leitura"
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
                do { extracted.append(try ShowPDFImporter.extractPreset(from: url)) }
                catch { failures.append(error.localizedDescription) }
                await Task.yield()
            }
            let ids = model.importExtractedShowPresets(extracted)
            if let first = ids.first, let preset = model.showPresets.first(where: { $0.id == first }) {
                onEditMusicFromLibrary(preset)
            }
            if !failures.isEmpty { model.lastError = failures.joined(separator: "\n") }
            isImportingPDF = false
        }
    }
}

struct ShowMusicEditorPanel: View {
    @EnvironmentObject private var model: AppModel
    @Binding var draft: ShowPreset
    @Binding var chartEditorText: String
    let onSave: () -> Void
    let onSaveAndTest: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    let onConfirm: () -> Void

    @State private var isStyleBrowserPresented = false
    @State private var chartTransposeSteps = 0
    @State private var confirmsChartRestore = false

    private var selectedStyle: ArrangerStyle? {
        draft.arrangerStyleID.flatMap { id in model.arrangerStyles.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.songTitle.isEmpty ? "Nova música" : draft.songTitle)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                    Text("Rascunho local · salvar não envia MIDI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fechar editor", systemImage: "xmark", action: onCancel)
                    .labelStyle(.iconOnly)
            }
            .padding(18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    executionSection
                    styleSection
                    effectsSection
                    chartSection
                    Button("Excluir música", systemImage: "trash", role: .destructive, action: onDelete)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(18)
            }

            Divider()

            HStack(spacing: 10) {
                Button("Cancelar", action: onCancel)
                Spacer()
                if model.pendingShowConfirmationID == draft.id {
                    Button("Confirmar no PA700", systemImage: "checkmark.seal.fill", action: onConfirm)
                        .tint(LabTheme.verified)
                }
                Button("Salvar e testar", systemImage: "play.fill", action: onSaveAndTest)
                    .disabled(!model.connected || (!draft.hasDirectSetup && draft.songBookNumber == nil))
                Button("Salvar", systemImage: "square.and.arrow.down", action: onSave)
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .confirmationDialog("Restaurar a cifra importada?", isPresented: $confirmsChartRestore) {
            Button("Restaurar original", role: .destructive) { restoreOriginalChart() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("As alterações locais da cifra serão substituídas no rascunho.")
        }
        .background(LabTheme.stageSurface)
    }

    private var executionSection: some View {
        GroupBox("Música e execução") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Música") { TextField("Nome da música", text: $draft.songTitle).textFieldStyle(.roundedBorder) }
                LabeledContent("Tom da cifra") { TextField("Ex.: G, F#m", text: $draft.originalKey).textFieldStyle(.roundedBorder) }
                LabeledContent("SongBook") { TextField("Opcional", text: songBookBinding).textFieldStyle(.roundedBorder) }
                LabeledContent("Transpose") {
                    HStack {
                        Text(signed(draft.transposeSemitones)).font(.body.monospacedDigit()).frame(width: 34)
                        Stepper("Transpose", value: $draft.transposeSemitones, in: -12...12).labelsHidden()
                    }
                }
            }
            .padding(8)
        }
    }

    private var styleSection: some View {
        GroupBox("Style e Keyboard Set") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Style") {
                    HStack {
                        Button {
                            isStyleBrowserPresented = true
                        } label: {
                            HStack {
                                Image(systemName: "music.quarternote.3").foregroundStyle(LabTheme.signal)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selectedStyle?.displayName ?? "Selecionar Style")
                                    Text(styleDetail).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").font(.caption)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: LabTheme.radius))
                        .popover(isPresented: $isStyleBrowserPresented, arrowEdge: .trailing) {
                            ShowStyleBrowser(styles: model.arrangerStyles, selectedStyleID: draft.arrangerStyleID) { style in
                                draft.arrangerStyleID = style.id
                                if draft.keyboardSetSlot == nil { draft.keyboardSetSlot = 1 }
                                isStyleBrowserPresented = false
                            }
                        }
                        if selectedStyle != nil {
                            Button("Remover Style", systemImage: "xmark") {
                                draft.arrangerStyleID = nil
                                draft.keyboardSetSlot = nil
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                }
                LabeledContent("Keyboard Set") {
                    Picker("Keyboard Set", selection: keyboardSetBinding) {
                        ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(selectedStyle == nil)
                }
                Text(selectedStyle == nil ? "Selecione Factory ou User, depois o banco e o Style." : "Upper e Lower vêm do Keyboard Set escolhido dentro do Style.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private var effectsSection: some View {
        GroupBox("Efeitos e notas") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Efeitos") { TextField("Ex.: reverb curto", text: $draft.effectsSummary, axis: .vertical).textFieldStyle(.roundedBorder) }
                LabeledContent("Notas") { TextField("Lembretes para a execução", text: $draft.notes, axis: .vertical).textFieldStyle(.roundedBorder) }
            }
            .padding(8)
        }
    }

    private var chartSection: some View {
        GroupBox("Cifra e letra") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Toggle("Mostrar cifras", isOn: $draft.readerSettings.showChords)
                    Spacer()
                    Button("Restaurar original", systemImage: "arrow.uturn.backward") { confirmsChartRestore = true }
                        .disabled(model.originalShowChart(for: draft) == nil)
                }
                HStack {
                    Text("Transpor cifra")
                    Text(signed(chartTransposeSteps)).font(.callout.monospacedDigit()).frame(width: 32)
                    Stepper("Semitons da cifra", value: $chartTransposeSteps, in: -11...11).labelsHidden()
                    Button("Aplicar") { transposeChart() }
                        .disabled(chartTransposeSteps == 0 || ShowMusicTheory.transposedKey(draft.originalKey, by: chartTransposeSteps) == nil)
                }
                Text("# inicia uma seção; > inicia uma linha de acordes.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $chartEditorText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 320)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: LabTheme.radius))
                    .accessibilityLabel("Editor de cifra e letra")
                LabeledContent("Tamanho no Show") {
                    HStack {
                        Slider(value: $draft.readerSettings.fontScale, in: 0.75...2, step: 0.05)
                        Text("\(Int(draft.readerSettings.fontScale * 100))%").font(.caption.monospacedDigit())
                    }
                }
            }
            .padding(8)
        }
    }

    private var songBookBinding: Binding<String> {
        Binding(
            get: { draft.songBookNumber.map(String.init) ?? "" },
            set: { value in
                let digits = value.filter(\.isNumber)
                draft.songBookNumber = digits.isEmpty ? nil : Int(digits)
            }
        )
    }

    private var keyboardSetBinding: Binding<Int> {
        Binding(get: { draft.keyboardSetSlot ?? 1 }, set: { draft.keyboardSetSlot = $0 })
    }

    private var styleDetail: String {
        guard let style = selectedStyle else { return "Factory ou User › Style" }
        if let bank = style.userBankName { return "User › \(bank) › \(style.displayName)" }
        return "Factory › \(style.category) › \(style.displayName)"
    }

    private func restoreOriginalChart() {
        guard let lines = model.originalShowChart(for: draft) else { return }
        draft.chartLines = lines
        chartEditorText = ShowChartLine.editorText(from: lines)
        chartTransposeSteps = 0
    }

    private func transposeChart() {
        guard chartTransposeSteps != 0,
              let target = ShowMusicTheory.transposedKey(draft.originalKey, by: chartTransposeSteps) else { return }
        let lines = ShowChartLine.parseEditorText(chartEditorText)
        draft.chartLines = ShowMusicTheory.transposeChart(lines, by: chartTransposeSteps, preferFlats: target.contains("b"))
        draft.originalKey = target
        chartEditorText = ShowChartLine.editorText(from: draft.chartLines)
        chartTransposeSteps = 0
    }

    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }
}
