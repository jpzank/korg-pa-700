import ArrangerLabCore
import AppKit
import SwiftUI

private struct ShowSetListRowFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private enum PendingShowWorkspaceAction: Equatable {
    case closeEditor
    case mode(ShowWorkspaceMode)
    case editMusic(UUID, returnToLibrary: Bool)
    case newMusic(returnToLibrary: Bool)
    case openSetListItem(UUID)
    case selectRepertoire(UUID?)
}

struct ShowView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focusedItemID: UUID?
    @AppStorage("arrangerlab.showReaderFontSize") private var readerFontSize = 23.0
    @AppStorage("arrangerlab.showFocusReaderFontSize") private var focusReaderFontSize = 29.0
    @AppStorage("arrangerlab.showReaderChords") private var showChords = true
    @AppStorage("arrangerlab.showAutoScrollSpeed") private var autoScrollSpeedRawValue = ShowAutoScrollSpeed.normal.rawValue
    @State private var chartPositions: [UUID: Int] = [:]
    @State private var readingItemID: UUID?
    @State private var focusMode = false
    @State private var focusChromeVisible = true
    @State private var focusPointerAtTop = false
    @State private var focusChromeHideTask: Task<Void, Never>?
    @State private var autoScrollEnabled = false
    @State private var editingAnnotations = false
    @State private var editingChart = false
    @State private var editorPresented = false
    @State private var libraryPresented = false
    @State private var editorReturnsToLibrary = false
    @State private var editorDraft = ShowPreset(songTitle: "")
    @State private var editorOriginal = ShowPreset(songTitle: "")
    @State private var editorChartText = ""
    @State private var pendingWorkspaceAction: PendingShowWorkspaceAction?
    @State private var presetPendingDeletion: ShowPreset?
    @State private var suppressWorkspaceModeGuard = false
    @State private var draggedSetListItemID: UUID?
    @State private var setListRowFrames: [UUID: CGRect] = [:]

    var body: some View {
        VStack(spacing: 0) {
            if !focusMode || focusChromeVisible {
                ShowConnectionStrip(
                    workspaceMode: model.showWorkspaceMode,
                    focusMode: focusMode,
                    onSelectWorkspaceMode: requestWorkspaceMode,
                    onToggleFocus: toggleFocusMode,
                    onFullScreen: enterFullScreen
                )
                Divider()
            }

            if model.showWorkspaceMode == .show {
                ShowPA700LiveStateStrip(
                    state: model.pa700LiveState,
                    commandedState: model.pa700CommandedShowState,
                    commandedSummary: commandedShowSummary,
                    isConnected: model.connected && model.pa700ConnectionHealth == .confirmed
                )
                Divider()
            }

            if model.showWorkspaceMode == .repertoire {
                ShowRepertoireWorkspace(
                    isLibraryPresented: $libraryPresented,
                    onEditMusicFromOrder: { requestEditMusic($0, returnToLibrary: false) },
                    onEditMusicFromLibrary: { requestEditMusic($0, returnToLibrary: true) },
                    onNewMusicFromLibrary: { requestNewMusic(returnToLibrary: true) },
                    onSelectRepertoire: { requestWorkspaceAction(.selectRepertoire($0)) },
                    onStartShow: startShow
                )
            } else {
                if let setList = model.activeShowSetList {
                    showContent(setList)
                } else {
                    emptyState
                }
            }
        }
        .tint(LabTheme.signal)
        .preferredColorScheme(.dark)
        .background {
            ZStack {
                ShowKeyboardMonitor(
                    enabled: model.showWorkspaceMode == .show && !editingAnnotations && !editingChart,
                    performanceMode: focusMode
                ) { action in
                    handlePerformanceKey(action)
                }
                ShowMouseMovementMonitor(enabled: focusMode) { isAtTopEdge in
                    updateFocusChromeForPointer(isAtTopEdge)
                }
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        .alert("Arranger Lab", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
        .overlay(alignment: .trailing) {
            if editorPresented {
                ShowMusicEditorPanel(
                    draft: $editorDraft,
                    chartEditorText: $editorChartText,
                    onSave: { saveEditorAndReturnIfNeeded() },
                    onSaveAndTest: { _ = saveEditor(testAfterSaving: true) },
                    onCancel: { requestWorkspaceAction(.closeEditor) },
                    onDelete: { presetPendingDeletion = savedEditorPreset },
                    onConfirm: confirmEditorPreset
                )
                .environmentObject(model)
                .frame(width: 500)
                .shadow(color: .black.opacity(0.45), radius: 18, x: -6)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: editorPresented)
        .confirmationDialog(
            "Salvar alterações desta música?",
            isPresented: Binding(get: { pendingWorkspaceAction != nil }, set: { if !$0 { pendingWorkspaceAction = nil } })
        ) {
            Button("Salvar") {
                completePendingWorkspaceAction(saving: true)
            }
            Button("Descartar", role: .destructive) {
                completePendingWorkspaceAction(saving: false)
            }
            Button("Cancelar", role: .cancel) { pendingWorkspaceAction = nil }
        } message: {
            Text("O rascunho tem alterações que ainda não foram salvas.")
        }
        .confirmationDialog(
            "Excluir \(presetPendingDeletion?.songTitle ?? "esta música")?",
            isPresented: Binding(get: { presetPendingDeletion != nil }, set: { if !$0 { presetPendingDeletion = nil } })
        ) {
            Button("Excluir música", role: .destructive) {
                if let presetPendingDeletion { model.deleteShowPreset(presetPendingDeletion) }
                presetPendingDeletion = nil
                closeEditorReturningToOrigin()
            }
            Button("Cancelar", role: .cancel) { presetPendingDeletion = nil }
        } message: {
            Text("Ela também será removida de todos os repertórios. Esta ação não pode ser desfeita.")
        }
        .onAppear {
            selectCurrentOrFirstItem()
            loadReaderDefaults()
        }
        .onChange(of: model.activeShowSetListID) { _, _ in selectCurrentOrFirstItem() }
        .onChange(of: model.showStartRequestID) { _, _ in
            selectCurrentOrFirstItem()
            loadReaderDefaults()
        }
        .onChange(of: model.activeShowSetListItemID) { _, newValue in
            if let newValue {
                focusedItemID = newValue
                readingItemID = newValue
            }
        }
        .onChange(of: readingItemID) { _, _ in
            editingAnnotations = false
            editingChart = false
            loadReaderDefaults()
        }
        .onChange(of: editingAnnotations) { _, isEditing in
            updateFocusChromeForEditing(isEditing || editingChart)
        }
        .onChange(of: editingChart) { _, isEditing in
            updateFocusChromeForEditing(isEditing || editingAnnotations)
        }
        .onChange(of: model.showWorkspaceMode) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if suppressWorkspaceModeGuard {
                suppressWorkspaceModeGuard = false
                if newValue == .show { selectCurrentOrFirstItem() }
                return
            }
            if editorPresented && editorIsDirty {
                suppressWorkspaceModeGuard = true
                model.showWorkspaceMode = oldValue
                pendingWorkspaceAction = .mode(newValue)
            } else {
                if newValue != .repertoire { libraryPresented = false }
                if newValue == .show { selectCurrentOrFirstItem() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            focusMode = false
            focusChromeVisible = true
            focusPointerAtTop = false
            focusChromeHideTask?.cancel()
            editingAnnotations = false
            editingChart = false
        }
        .onDisappear {
            focusChromeHideTask?.cancel()
        }
    }

    private func showContent(_ setList: ShowSetList) -> some View {
        GeometryReader { geometry in
            if focusMode {
                chartStage(readingPreset(in: setList), setList: setList)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    setListRail(setList)
                        .frame(width: geometry.size.width < 1_120 ? 270 : 300)

                    Divider()

                    chartStage(readingPreset(in: setList), setList: setList)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if geometry.size.width >= 1_180 && !editorPresented {
                        Divider()

                        presetPanel(setList, displayedPreset: readingPreset(in: setList))
                            .frame(width: 310)
                    }
                }
            }
        }
    }

    private func setListRail(_ setList: ShowSetList) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(setList.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                HStack {
                    Text("\(setList.items.count) músicas")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Repertório", selection: activeSetListBinding) {
                        ForEach(model.showSetLists) { candidate in
                            Text(candidate.name).tag(Optional(candidate.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 132)
                    .accessibilityLabel("Repertório ativo")
                }
            }
            .padding(18)

            Divider()

            if setList.items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Repertório vazio")
                        .font(.headline)
                    Text("Adicione músicas no modo Repertório.")
                        .foregroundStyle(.secondary)
                    Button("Abrir Repertório", systemImage: "slider.horizontal.3") {
                        requestWorkspaceMode(.repertoire)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(Array(setList.items.enumerated()), id: \.element.id) { index, item in
                            showRow(index: index, item: item, setList: setList)
                                .id(item.id)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .onPreferenceChange(ShowSetListRowFramesKey.self) {
                        setListRowFrames = $0
                    }
                    .onMoveCommand { direction in
                        guard let itemID = moveFocus(direction, in: setList) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(itemID, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 7) {
                Image(systemName: readingStatusIcon)
                    .foregroundStyle(readingStatusColor)
                Text(model.showStatus)
                    .font(.caption)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(minHeight: 52)
        }
        .background(LabTheme.stageSurface.opacity(0.72))
    }

    private func showRow(index: Int, item: ShowSetListItem, setList: ShowSetList) -> some View {
        let preset = model.showPreset(for: item)
        let isActive = model.activeShowSetListItemID == item.id
        let isReading = readingItemID == item.id
        let isReady = preset?.isReadyToPlay == true
        let accessibilityTitle = "\(index + 1), \(preset?.songTitle ?? "Preset indisponível")"
        let accessibilityStatus = isActive ? "Aplicada no PA700" : (isReady ? "Configurada" : "Somente leitura")
        let accessibilityHelp = isReady
            ? "Abre a letra e a cifra. Use Aplicar no PA700 para enviar a configuração."
            : "Abre a letra e a cifra sem enviar nada ao PA700."
        let openForReading: () -> Void = {
            guard !editingChart, preset != nil else { return }
            requestWorkspaceAction(.openSetListItem(item.id))
        }

        return HStack(spacing: 11) {
            Text(String(format: "%02d", index + 1))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(isActive ? LabTheme.verified : .secondary)
                .frame(width: 26, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                Text(preset?.songTitle ?? "Preset indisponível")
                    .font(.callout.weight(isActive ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(setupLabel(preset))
                    Text("·")
                    Text(isActive ? "No PA700" : (isReady ? "Configurada" : "Somente leitura"))
                        .foregroundStyle(isActive ? LabTheme.verified : (isReady ? Color.secondary : LabTheme.draft))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                if let preset {
                    HStack(spacing: 6) {
                        Text("Mão \(preset.originalKey.isEmpty ? "?" : preset.originalKey)")
                        Text("T \(signedSemitones(preset.transposeSemitones))")
                        Text("Soa \(soundingKey(preset) ?? "?")")
                    }
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(isActive ? LabTheme.signal : .secondary)
                }
            }

            Spacer(minLength: 4)

            showRowDragHandle(item: item, preset: preset, setList: setList)

            Image(systemName: rowIcon(isActive: isActive, isReading: isReading, isReady: isReady))
                .foregroundStyle(rowIconColor(isActive: isActive, isReading: isReading, isReady: isReady))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(
            isReading
                ? LabTheme.signal.opacity(0.17)
                : (isActive ? LabTheme.verified.opacity(0.10) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: openForReading)
        .allowsHitTesting(!editingChart)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ShowSetListRowFramesKey.self,
                    value: [item.id: geometry.frame(in: .global)]
                )
            }
        }
        .overlay(alignment: .bottom) { Divider().opacity(0.55) }
        .focusable()
        .focused($focusedItemID, equals: item.id)
        .onKeyPress(.return) {
            openForReading()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilityStatus)
        .accessibilityHint(accessibilityHelp)
        .accessibilityAction(named: "Abrir cifra", openForReading)
        .accessibilityAction(named: "Mover para cima") {
            model.moveShowSetListItem(item, in: setList, offset: -1)
        }
        .accessibilityAction(named: "Mover para baixo") {
            model.moveShowSetListItem(item, in: setList, offset: 1)
        }
    }

    private func showRowDragHandle(
        item: ShowSetListItem,
        preset: ShowPreset?,
        setList: ShowSetList
    ) -> some View {
        let accessibilityLabel = "Arrastar \(preset?.songTitle ?? "música")"
        let color: Color = draggedSetListItemID == item.id ? LabTheme.signal : .secondary

        return Image(systemName: "line.3.horizontal")
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 32, height: 52)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { _ in
                        draggedSetListItemID = item.id
                    }
                    .onEnded { value in
                        moveShowSetListItem(
                            item,
                            in: setList,
                            toGlobalY: value.location.y
                        )
                        draggedSetListItemID = nil
                    }
            )
            .help("Arraste para mudar a ordem")
            .accessibilityLabel(accessibilityLabel)
    }

    private func moveShowSetListItem(
        _ item: ShowSetListItem,
        in setList: ShowSetList,
        toGlobalY globalY: CGFloat
    ) {
        guard let sourceIndex = setList.items.firstIndex(where: { $0.id == item.id }),
              let target = setList.items
                .compactMap({ candidate -> (item: ShowSetListItem, frame: CGRect)? in
                    guard let frame = setListRowFrames[candidate.id] else { return nil }
                    return (candidate, frame)
                })
                .min(by: {
                    abs($0.frame.midY - globalY) < abs($1.frame.midY - globalY)
                }),
              let targetIndex = setList.items.firstIndex(where: { $0.id == target.item.id })
        else {
            return
        }

        let destination = targetIndex + (globalY > target.frame.midY ? 1 : 0)
        guard sourceIndex != targetIndex || destination != sourceIndex else { return }

        withAnimation(.easeOut(duration: 0.14)) {
            model.moveShowSetListItems(
                in: setList,
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: destination
            )
        }
    }

    private func chartStage(_ preset: ShowPreset?, setList: ShowSetList) -> some View {
        Group {
            if let preset {
                ShowChartReader(
                    preset: preset,
                    applicationState: readingApplicationState,
                    isConnected: model.connected && model.pa700ConnectionHealth == .confirmed,
                    focusMode: focusMode,
                    showsChrome: !focusMode || focusChromeVisible,
                    showChords: $showChords,
                    fontSize: activeReaderFontSize,
                    editingAnnotations: $editingAnnotations,
                    editingChart: $editingChart,
                    annotations: annotationBinding(for: preset),
                    position: Binding(
                        get: { chartPositions[preset.id] ?? 0 },
                        set: { chartPositions[preset.id] = $0 }
                    ),
                    autoScrollEnabled: $autoScrollEnabled,
                    autoScrollSpeed: autoScrollSpeedBinding,
                    progressText: progressText(in: setList),
                    nextTitle: nextPreset(in: setList)?.songTitle,
                    canGoPrevious: canNavigate(by: -1, in: setList),
                    canGoNext: canNavigate(by: 1, in: setList),
                    onPrevious: { navigate(by: -1, in: setList) },
                    onNext: { navigate(by: 1, in: setList) },
                    onSetChartKey: { model.setShowChartKey(presetID: preset.id, key: $0) },
                    onTransposeChart: { model.transposeShowChart(presetID: preset.id, by: $0) },
                    onAdjustTranspose: { model.adjustShowTranspose(presetID: preset.id, by: $0) },
                    onSaveChartDraft: { model.saveShowChartDraft(presetID: preset.id, text: $0) },
                    onApply: { model.applyShowPreset(preset, setListItemID: readingItemID) }
                )
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Selecione uma música")
                        .font(.title2.weight(.semibold))
                    Text("A letra e a cifra abrem sem enviar nada. Somente músicas prontas acionam o PA700.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                    if !model.connected {
                        Label("Reconecte o PA700 para iniciar", systemImage: "cable.connector.slash")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(LabTheme.draft)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(LabTheme.stageBackground)
    }

    private func presetPanel(_ setList: ShowSetList, displayedPreset: ShowPreset?) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(displayedPreset.map { _ in readingApplicationLabel } ?? "MÚSICA")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            if let preset = displayedPreset {
                Button("Editar música", systemImage: "pencil") { requestEditMusic(preset) }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                VStack(alignment: .leading, spacing: 6) {
                    Text(preset.songTitle)
                        .font(.title2.weight(.semibold))
                        .lineLimit(3)
                    HStack(spacing: 7) {
                        Text(setupLabel(preset))
                        Text("Transpose \(signedSemitones(preset.transposeSemitones))")
                    }
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(LabTheme.signal)
                    Text("Mãos: \(preset.originalKey.isEmpty ? "?" : preset.originalKey)  ·  Soa: \(soundingKey(preset) ?? "?")")
                        .font(.callout.monospaced().weight(.semibold))
                        .foregroundStyle(.primary)
                    if readingApplicationState != .current {
                        Label(
                            readingApplicationState == .stale ? "Último envio desatualizado" : "Não enviada ao PA700",
                            systemImage: readingApplicationState == .stale ? "clock.arrow.circlepath" : "doc.text"
                        )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LabTheme.draft)
                    }
                }

                Divider()

                if preset.hasDirectSetup {
                    VStack(spacing: 10) {
                        showHierarchyRow(
                            label: "Style",
                            value: styleDisplayName(for: preset),
                            detail: styleCategory(for: preset)
                        )
                        showHierarchyRow(
                            label: "Kbd Set",
                            value: "Keyboard Set \(preset.keyboardSetSlot ?? 1)",
                            detail: "Define Upper 1, Upper 2, Upper 3 e Lower"
                        )
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(preset.parts) { part in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(part.part.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 60, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(part.isEnabled ? (part.displayName.isEmpty ? "Não informado" : part.displayName) : "Desligado")
                                        .font(.callout)
                                        .foregroundStyle(part.isEnabled ? .primary : .secondary)
                                        .lineLimit(2)
                                    if part.isEnabled, let library = part.soundLibrary, !library.isEmpty {
                                        Text(library)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(LabTheme.signal)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                detailBlock(title: "EFEITOS", value: preset.effectsSummary.isEmpty ? "Não informado" : preset.effectsSummary)
                detailBlock(title: "NOTAS", value: preset.notes.isEmpty ? "Sem notas" : preset.notes)
            } else {
                Text("Nenhuma música selecionada")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            if let next = nextPreset(in: setList) {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("A SEGUIR")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(next.songTitle)
                        .font(.headline)
                    HStack(spacing: 7) {
                        Text(setupLabel(next))
                        Text(transposeText(next.transposeSemitones))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            if let commanded = model.pa700CommandedShowState,
               !isReadingCommandedSnapshot {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text(commanded.status == .current ? "APLICADA PELO APP" : "ÚLTIMO ENVIO")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(commanded.status == .current ? LabTheme.signal : LabTheme.draft)
                    Text(commanded.preset.songTitle)
                        .font(.headline)
                        .lineLimit(2)
                    Text("\(setupLabel(commanded.preset)) · \(transposeText(commanded.preset.transposeSemitones))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(22)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(LabTheme.stageSurface.opacity(0.78))
    }

    private func detailBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .lineLimit(6)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 44))
                .foregroundStyle(LabTheme.signal)
            Text("Prepare seu repertório")
                .font(.title2.weight(.semibold))
            Text("Os repertórios Showboat Jul 23 e Boteco Jul3 são restaurados automaticamente.")
                .foregroundStyle(.secondary)
            Button("Importar Showboat Jul 23", systemImage: "square.and.arrow.down") {
                model.importShowboatJul23Catalog()
            }
            .buttonStyle(.borderedProminent)
            Button("Organizar repertórios", systemImage: "music.note.list") {
                requestWorkspaceMode(.repertoire)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var activeSetListBinding: Binding<UUID?> {
        Binding(get: { model.activeShowSetListID }, set: { model.selectShowSetList($0) })
    }

    private func nextPreset(in setList: ShowSetList) -> ShowPreset? {
        guard let referenceID = readingItemID ?? model.activeShowSetListItemID,
              let index = setList.items.firstIndex(where: { $0.id == referenceID }),
              setList.items.indices.contains(index + 1) else { return nil }
        return model.showPreset(for: setList.items[index + 1])
    }

    private func selectCurrentOrFirstItem() {
        let itemID = model.activeShowSetListItemID ?? model.activeShowSetList?.items.first?.id
        focusedItemID = itemID
        readingItemID = itemID
        if model.activeShowSetListItemID == nil,
           let setList = model.activeShowSetList,
           let preset = readingPreset(in: setList) {
            model.openShowPresetForReading(preset)
        }
    }

    private var savedEditorPreset: ShowPreset? {
        model.showPresets.first { $0.id == editorDraft.id }
    }

    private var editorIsDirty: Bool {
        var normalized = editorDraft
        normalized.chartLines = editorOriginal.chartLines
        let editedChart = ShowChartLine.parseEditorText(editorChartText)
        let chartChanged = !ShowChartLine.hasSameEditorContent(editedChart, editorOriginal.chartLines)
        return chartChanged || normalized != editorOriginal
    }

    private func requestWorkspaceMode(_ mode: ShowWorkspaceMode) {
        guard mode != model.showWorkspaceMode else { return }
        requestWorkspaceAction(.mode(mode))
    }

    private func requestEditMusic(_ preset: ShowPreset, returnToLibrary: Bool = false) {
        requestWorkspaceAction(.editMusic(preset.id, returnToLibrary: returnToLibrary))
    }

    private func requestNewMusic(returnToLibrary: Bool = false) {
        requestWorkspaceAction(.newMusic(returnToLibrary: returnToLibrary))
    }

    private func requestWorkspaceAction(_ action: PendingShowWorkspaceAction) {
        if editorPresented && editorIsDirty {
            pendingWorkspaceAction = action
        } else {
            performWorkspaceAction(action)
        }
    }

    private func completePendingWorkspaceAction(saving: Bool) {
        guard let action = pendingWorkspaceAction else { return }
        if saving {
            guard saveEditor(testAfterSaving: false) else { return }
        } else {
            editorDraft = editorOriginal
            editorChartText = ShowChartLine.editorText(from: editorOriginal.chartLines)
        }
        pendingWorkspaceAction = nil
        performWorkspaceAction(action)
    }

    private func performWorkspaceAction(_ action: PendingShowWorkspaceAction) {
        switch action {
        case .closeEditor:
            closeEditorReturningToOrigin()
        case let .mode(mode):
            editorPresented = false
            libraryPresented = false
            editorReturnsToLibrary = false
            model.showWorkspaceMode = mode
        case let .editMusic(id, returnToLibrary):
            guard let preset = model.showPresets.first(where: { $0.id == id }) else { return }
            libraryPresented = false
            editorReturnsToLibrary = returnToLibrary
            editorDraft = preset
            editorOriginal = preset
            editorChartText = ShowChartLine.editorText(from: preset.chartLines)
            editorPresented = true
        case let .newMusic(returnToLibrary):
            let preset = ShowPreset(songTitle: "")
            libraryPresented = false
            editorReturnsToLibrary = returnToLibrary
            editorDraft = preset
            editorOriginal = preset
            editorChartText = ""
            editorPresented = true
        case let .openSetListItem(itemID):
            guard let setList = model.activeShowSetList,
                  let item = setList.items.first(where: { $0.id == itemID }),
                  let preset = model.showPreset(for: item) else { return }
            focusedItemID = item.id
            readingItemID = item.id
            editingAnnotations = false
            editingChart = false
            model.openShowPresetForReading(preset)
            if editorPresented {
                editorDraft = preset
                editorOriginal = preset
                editorChartText = ShowChartLine.editorText(from: preset.chartLines)
            }
        case let .selectRepertoire(id):
            model.selectShowSetList(id)
        }
    }

    private func saveEditorAndReturnIfNeeded() {
        guard saveEditor(testAfterSaving: false) else { return }
        if editorReturnsToLibrary { closeEditorReturningToOrigin() }
    }

    private func closeEditorReturningToOrigin() {
        editorPresented = false
        if editorReturnsToLibrary && model.showWorkspaceMode == .repertoire {
            libraryPresented = true
        }
        editorReturnsToLibrary = false
    }

    @discardableResult
    private func saveEditor(testAfterSaving: Bool) -> Bool {
        editorDraft.chartLines = ShowChartLine.parseEditorText(editorChartText)
        guard model.saveShowPreset(editorDraft),
              let saved = model.showPresets.first(where: { $0.id == editorDraft.id }) else { return false }
        editorDraft = saved
        editorOriginal = saved
        editorChartText = ShowChartLine.editorText(from: saved.chartLines)
        if testAfterSaving { _ = model.testShowPreset(saved) }
        return true
    }

    private func confirmEditorPreset() {
        guard let savedEditorPreset, model.confirmShowPreset(savedEditorPreset),
              let confirmed = model.showPresets.first(where: { $0.id == savedEditorPreset.id }) else { return }
        editorDraft = confirmed
        editorOriginal = confirmed
    }

    private func startShow(_ setListID: UUID) {
        model.startShowSetList(setListID)
        requestWorkspaceMode(.show)
    }

    private func loadReaderDefaults() {
        guard let setList = model.activeShowSetList,
              let preset = readingPreset(in: setList) else { return }
        showChords = preset.readerSettings.showChords
        readerFontSize = min(37, max(17, 23 * preset.readerSettings.fontScale))
    }

    @discardableResult
    private func moveFocus(_ direction: MoveCommandDirection, in setList: ShowSetList) -> UUID? {
        guard !editingChart, !setList.items.isEmpty else { return nil }
        let referenceID = focusedItemID ?? readingItemID ?? model.activeShowSetListItemID
        let currentIndex = referenceID.flatMap { id in
            setList.items.firstIndex(where: { $0.id == id })
        } ?? 0
        let nextIndex: Int
        switch direction {
        case .up: nextIndex = max(0, currentIndex - 1)
        case .down: nextIndex = min(setList.items.count - 1, currentIndex + 1)
        default: return nil
        }
        let item = setList.items[nextIndex]
        requestWorkspaceAction(.openSetListItem(item.id))
        return item.id
    }

    private func navigate(by offset: Int, in setList: ShowSetList) {
        guard let referenceID = readingItemID ?? model.activeShowSetListItemID,
              let index = setList.items.firstIndex(where: { $0.id == referenceID }) else { return }
        let destination = index + offset
        guard setList.items.indices.contains(destination) else { return }
        let item = setList.items[destination]
        requestWorkspaceAction(.openSetListItem(item.id))
    }

    private func canNavigate(by offset: Int, in setList: ShowSetList) -> Bool {
        guard let referenceID = readingItemID ?? model.activeShowSetListItemID,
              let index = setList.items.firstIndex(where: { $0.id == referenceID }) else { return false }
        return setList.items.indices.contains(index + offset)
    }

    private func pageReadingChart(by amount: Int) {
        guard let setList = model.activeShowSetList,
              let preset = readingPreset(in: setList) else { return }
        let visibleLineCount = ShowChartLine
            .removingImportArtifacts(from: preset.chartLines)
            .filter { showChords || $0.kind != .chords }
            .count
        let currentPosition = chartPositions[preset.id] ?? 0
        chartPositions[preset.id] = min(
            max(0, currentPosition + amount),
            max(0, visibleLineCount - 1 + (focusMode ? 1 : 0))
        )
    }

    private func progressText(in setList: ShowSetList) -> String {
        guard let referenceID = readingItemID ?? model.activeShowSetListItemID,
              let index = setList.items.firstIndex(where: { $0.id == referenceID }) else {
            return "0 / \(setList.items.count)"
        }
        return "\(index + 1) / \(setList.items.count)"
    }

    private func annotationBinding(for preset: ShowPreset) -> Binding<[ShowChartAnnotation]> {
        Binding(
            get: {
                model.showPresets.first(where: { $0.id == preset.id })?.chartAnnotations ?? preset.chartAnnotations
            },
            set: { model.updateShowAnnotations(presetID: preset.id, annotations: $0) }
        )
    }

    private func enterFullScreen() {
        focusMode = true
        focusChromeVisible = true
        focusPointerAtTop = false
        editingAnnotations = false
        editingChart = false
        scheduleFocusChromeHide(after: .milliseconds(2_400))
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    private func toggleFocusMode() {
        editingAnnotations = false
        editingChart = false
        focusMode.toggle()
        focusChromeVisible = true
        focusPointerAtTop = false
        if focusMode {
            scheduleFocusChromeHide(after: .milliseconds(2_400))
        } else {
            focusChromeHideTask?.cancel()
        }
    }

    private func revealFocusChrome() {
        guard focusMode else { return }
        if !focusChromeVisible {
            withAnimation(.easeOut(duration: 0.16)) { focusChromeVisible = true }
        }
    }

    private func scheduleFocusChromeHide(after delay: Duration = .seconds(1.25)) {
        focusChromeHideTask?.cancel()
        guard focusMode, !focusPointerAtTop, !editingAnnotations, !editingChart else { return }
        focusChromeHideTask = Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
                guard !Task.isCancelled, focusMode, !focusPointerAtTop, !editingAnnotations, !editingChart else { return }
                withAnimation(.easeInOut(duration: 0.22)) { focusChromeVisible = false }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func updateFocusChromeForPointer(_ isAtTopEdge: Bool) {
        guard focusMode, isAtTopEdge != focusPointerAtTop else { return }
        focusPointerAtTop = isAtTopEdge
        if isAtTopEdge {
            focusChromeHideTask?.cancel()
            revealFocusChrome()
        } else {
            scheduleFocusChromeHide()
        }
    }

    private func updateFocusChromeForEditing(_ isEditing: Bool) {
        guard focusMode else { return }
        if isEditing {
            focusChromeHideTask?.cancel()
            focusChromeVisible = true
        } else {
            scheduleFocusChromeHide()
        }
    }

    private var autoScrollSpeedBinding: Binding<ShowAutoScrollSpeed> {
        Binding(
            get: { ShowAutoScrollSpeed(rawValue: autoScrollSpeedRawValue) ?? .normal },
            set: { autoScrollSpeedRawValue = $0.rawValue }
        )
    }

    private func handlePerformanceKey(_ action: ShowPerformanceKeyAction) {
        guard let setList = model.activeShowSetList else { return }
        switch action {
        case .applyCurrentPreset:
            guard let preset = readingPreset(in: setList) else { return }
            _ = model.applyShowPreset(preset, setListItemID: readingItemID)
        case let .page(amount):
            autoScrollEnabled = false
            pageReadingChart(by: amount)
        case .toggleAutoScroll:
            autoScrollEnabled.toggle()
        case let .adjustSpeed(offset):
            let speeds = ShowAutoScrollSpeed.allCases
            let current = speeds.firstIndex(of: autoScrollSpeedBinding.wrappedValue) ?? 0
            autoScrollSpeedBinding.wrappedValue = speeds[min(max(0, current + offset), speeds.count - 1)]
        case .previousSong:
            guard canNavigate(by: -1, in: setList) else { return }
            autoScrollEnabled = false
            navigate(by: -1, in: setList)
        case .nextSong:
            guard canNavigate(by: 1, in: setList) else { return }
            autoScrollEnabled = false
            navigate(by: 1, in: setList)
        case .top:
            guard let preset = readingPreset(in: setList) else { return }
            autoScrollEnabled = false
            chartPositions[preset.id] = 0
        case .toggleChrome:
            focusChromeHideTask?.cancel()
            withAnimation(.easeInOut(duration: 0.18)) { focusChromeVisible.toggle() }
        }
    }

    private var activeReaderFontSize: Binding<Double> {
        focusMode ? $focusReaderFontSize : $readerFontSize
    }

    private func readingPreset(in setList: ShowSetList) -> ShowPreset? {
        guard let itemID = readingItemID ?? model.activeShowSetListItemID,
              let item = setList.items.first(where: { $0.id == itemID }) else { return nil }
        return model.showPreset(for: item)
    }

    private var commandedShowSummary: String? {
        guard let commanded = model.pa700CommandedShowState else { return nil }
        return "\(setupLabel(commanded.preset)) · \(transposeText(commanded.preset.transposeSemitones))"
    }

    private var readingStatusIcon: String {
        guard readingItemID != nil else { return "circle.dashed" }
        return readingItemID == model.activeShowSetListItemID ? "checkmark.circle.fill" : "doc.text.fill"
    }

    private var readingStatusColor: Color {
        readingItemID == model.activeShowSetListItemID ? LabTheme.verified : LabTheme.signal
    }

    private var readingApplicationState: ShowPresetApplicationState {
        guard let commanded = model.pa700CommandedShowState,
              let setList = model.activeShowSetList,
              let preset = readingPreset(in: setList),
              let readingItemID,
              commanded.presetID == preset.id,
              commanded.setListItemID == readingItemID,
              commanded.preset == preset else { return .notApplied }
        return commanded.status == .current ? .current : .stale
    }

    private var isReadingCommandedSnapshot: Bool {
        guard let commanded = model.pa700CommandedShowState,
              let setList = model.activeShowSetList,
              let preset = readingPreset(in: setList),
              let readingItemID else { return false }
        return commanded.presetID == preset.id
            && commanded.setListItemID == readingItemID
            && commanded.preset == preset
    }

    private var readingApplicationLabel: String {
        switch readingApplicationState {
        case .notApplied: return "EM LEITURA"
        case .current: return "APLICADA PELO APP"
        case .stale: return "ÚLTIMO ENVIO"
        }
    }

    private func rowIcon(isActive: Bool, isReading: Bool, isReady: Bool) -> String {
        if isActive { return "checkmark.circle.fill" }
        if isReading { return "doc.text.fill" }
        return isReady ? "chevron.right" : "doc.text"
    }

    private func rowIconColor(isActive: Bool, isReading: Bool, isReady: Bool) -> Color {
        if isActive { return LabTheme.verified }
        if isReading { return LabTheme.signal }
        return .secondary
    }

    private func songBookLabel(_ number: Int?) -> String {
        number.map { "SB \($0)" } ?? "Sem SB"
    }

    private func setupLabel(_ preset: ShowPreset?) -> String {
        guard let preset else { return "Sem configuração" }
        if preset.hasDirectSetup {
            return "\(styleDisplayName(for: preset)) · Kbd \(preset.keyboardSetSlot ?? 1)"
        }
        return songBookLabel(preset.songBookNumber)
    }

    private func styleDisplayName(for preset: ShowPreset) -> String {
        guard let id = preset.arrangerStyleID else { return "Style" }
        return model.arrangerStyles.first { $0.id == id }?.displayName ?? id
    }

    private func styleCategory(for preset: ShowPreset) -> String {
        guard let id = preset.arrangerStyleID else { return "Sem categoria" }
        guard let style = model.arrangerStyles.first(where: { $0.id == id }) else { return "Style" }
        if let bank = style.userBankName { return "User › \(bank)" }
        return "Factory › \(style.category)"
    }

    private func showHierarchyRow(label: String, value: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(width: 60, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func transposeText(_ value: Int) -> String {
        value == 0 ? "Transp. 0" : "Transp. \(value > 0 ? "+" : "")\(value)"
    }

    private func soundingKey(_ preset: ShowPreset) -> String? {
        ShowMusicTheory.transposedKey(preset.originalKey, by: preset.transposeSemitones)
    }
}

private enum ShowAutoScrollSpeed: String, CaseIterable, Identifiable {
    case verySlow = "0,5×"
    case slow = "0,75×"
    case normal = "1×"
    case fast = "1,25×"
    case veryFast = "1,5×"

    var id: String { rawValue }
    var pointsPerSecond: CGFloat {
        switch self {
        case .verySlow: return 10
        case .slow: return 16
        case .normal: return 24
        case .fast: return 34
        case .veryFast: return 46
        }
    }

    var accessibilityName: String {
        switch self {
        case .verySlow: return "Muito lenta"
        case .slow: return "Lenta"
        case .normal: return "Normal"
        case .fast: return "Rápida"
        case .veryFast: return "Muito rápida"
        }
    }
}

private enum ShowPerformanceKeyAction {
    case applyCurrentPreset
    case page(Int)
    case toggleAutoScroll
    case adjustSpeed(Int)
    case previousSong
    case nextSong
    case top
    case toggleChrome
}

private enum ShowPresetApplicationState: Equatable {
    case notApplied
    case current
    case stale
}

private struct ShowChartReader: View {
    let preset: ShowPreset
    let applicationState: ShowPresetApplicationState
    let isConnected: Bool
    let focusMode: Bool
    let showsChrome: Bool
    @Binding var showChords: Bool
    @Binding var fontSize: Double
    @Binding var editingAnnotations: Bool
    @Binding var editingChart: Bool
    @Binding var annotations: [ShowChartAnnotation]
    @Binding var position: Int
    @Binding var autoScrollEnabled: Bool
    @Binding var autoScrollSpeed: ShowAutoScrollSpeed
    let progressText: String
    let nextTitle: String?
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSetChartKey: (String) -> Void
    let onTransposeChart: (Int) -> Void
    let onAdjustTranspose: (Int) -> Void
    let onSaveChartDraft: (String) -> Bool
    let onApply: () -> Void
    @State private var chartDraftText = ""
    @StateObject private var scrollDriver = ShowContinuousScrollDriver()

    private var allLines: [ShowChartLine] {
        ShowChartLine.removingImportArtifacts(from: preset.chartLines)
    }

    private var visibleLines: [ShowChartLine] {
        lines(showingChords: showChords)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsChrome {
                VStack(spacing: focusMode ? 9 : 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 9) {
                            Text(progressText)
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(preset.songTitle)
                                .font((focusMode ? Font.title : Font.title2).weight(.semibold))
                                .lineLimit(1)
                            Label(applicationBadge, systemImage: applicationBadgeIcon)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(applicationBadgeColor)
                        }
                        if focusMode {
                            Text(nextTitle.map { "A seguir: \($0)" } ?? "Última música do repertório")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary.opacity(0.78))
                                .lineLimit(1)
                        } else if let source = preset.source {
                            Text(source.sourceURL == nil
                                ? "Conteúdo extraído de \(source.documentName)"
                                : "Conteúdo importado de \(source.documentName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    HStack(spacing: 7) {
                        Button(action: onPrevious) {
                            Label("Anterior", systemImage: "chevron.left")
                        }
                        .disabled(!canGoPrevious || isEditingContent)
                        .keyboardShortcut(.leftArrow, modifiers: [.command])

                        Button(action: onNext) {
                            Label("Próxima", systemImage: "chevron.right")
                        }
                        .disabled(!canGoNext || isEditingContent)
                        .keyboardShortcut(.rightArrow, modifiers: [.command])

                        applicationButton
                    }
                    .controlSize(focusMode ? .large : .regular)
                }

                HStack(spacing: 8) {
                    HStack(spacing: 0) {
                        chartKeyMetric
                        Divider().frame(height: 34)
                        transposeMetric
                        Divider().frame(height: 34)
                        toneMetric(
                            label: "SOA",
                            value: ShowMusicTheory.transposedKey(preset.originalKey, by: preset.transposeSemitones) ?? "?",
                            color: LabTheme.verified
                        )
                    }
                    .disabled(editingChart)

                    Spacer(minLength: 8)

                    if editingChart {
                        Label("Editando rascunho", systemImage: "pencil")
                            .foregroundStyle(LabTheme.draft)
                        Button("Cancelar", role: .cancel, action: cancelChartDraft)
                            .keyboardShortcut(.cancelAction)
                        Button("Salvar rascunho", systemImage: "square.and.arrow.down", action: saveChartDraft)
                            .buttonStyle(.borderedProminent)
                            .tint(LabTheme.signal)
                            .keyboardShortcut("s", modifiers: [.command])
                    } else {
                        Toggle("Cifras", isOn: chordVisibilityBinding)
                            .toggleStyle(.button)
                            .help("Mostrar ou ocultar os acordes")
                        Button { fontSize = max(17, fontSize - 2) } label: {
                            Image(systemName: "textformat.size.smaller")
                        }
                        .help("Diminuir letra")
                        .disabled(fontSize <= 17)
                        Button { fontSize = min(47, fontSize + 2) } label: {
                            Image(systemName: "textformat.size.larger")
                        }
                        .help("Aumentar letra")
                        .disabled(fontSize >= 47)
                        Button("Topo", systemImage: "arrow.up.to.line") { position = 0 }
                            .help("Voltar ao início da cifra")

                        Divider().frame(height: 28)

                        Button("Editar cifra", systemImage: "pencil", action: beginChartDraft)
                            .help("Editar letra e acordes nesta tela")
                        Toggle(isOn: $editingAnnotations) {
                            Label("Anotar", systemImage: editingAnnotations ? "lock.open.fill" : "note.text")
                        }
                        .toggleStyle(.button)
                        .help(editingAnnotations ? "Concluir anotações" : "Editar anotações sobre a cifra")
                        if editingAnnotations {
                            Button("Nova nota", systemImage: "plus") { addAnnotation() }
                                .buttonStyle(.borderedProminent)
                                .tint(LabTheme.signal)
                        }
                    }

                }
                .controlSize(focusMode ? .large : .regular)
                }
                .padding(.horizontal, focusMode ? 28 : 22)
                .padding(.vertical, focusMode ? 11 : 14)
                .background(LabTheme.stageSurface.opacity(0.92))

                Divider()
            }

            if editingChart {
                chartDraftEditor
            } else if visibleLines.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("Cifra ainda não cadastrada")
                        .font(.headline)
                    Text("Use Editar música para cadastrar o conteúdo.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                if focusMode {
                                    chartDocumentHeader
                                        .id(preset.id)
                                }
                                ForEach(Array(visibleLines.enumerated()), id: \.element.id) { _, line in
                                    chartLine(line)
                                        .id(line.id)
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, focusMode ? 56 : 34)
                            .padding(.vertical, focusMode ? 36 : 28)
                            .frame(maxWidth: focusMode ? 1_080 : .infinity, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: focusMode ? .center : .leading)
                            .background(ShowScrollViewResolver(driver: scrollDriver))
                        }
                        .scrollPosition(id: visibleLineIDBinding, anchor: .top)
                        .focusable(!editingAnnotations)
                        .accessibilityLabel("Cifra de \(preset.songTitle)")
                        ForEach($annotations) { $annotation in
                            ShowAnnotationNote(
                                annotation: $annotation,
                                canvasSize: geometry.size,
                                isEditing: editingAnnotations,
                                onDelete: { deleteAnnotation(annotation.id) }
                            )
                        }

                        stageControls
                        .buttonStyle(.bordered)
                        .controlSize(focusMode ? .large : .regular)
                        .padding(focusMode ? 24 : 18)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: focusMode ? .bottom : .bottomTrailing
                        )
                        .allowsHitTesting(!editingAnnotations)
                    }
                }
            }
        }
        .onChange(of: preset.id) { _, _ in stopAutoScroll() }
        .onChange(of: autoScrollEnabled) { _, isEnabled in
            if isEnabled {
                startAutoScroll()
            } else {
                scrollDriver.stop()
            }
        }
        .onChange(of: autoScrollSpeed) { _, _ in
            scrollDriver.updateSpeed(autoScrollSpeed.pointsPerSecond)
        }
        .onChange(of: editingChart) { _, isEditing in if isEditing { stopAutoScroll() } }
        .onChange(of: editingAnnotations) { _, isEditing in if isEditing { stopAutoScroll() } }
        .onDisappear { scrollDriver.stop() }
    }

    private var chartDocumentHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(preset.songTitle)
                .font(.system(size: max(34, fontSize * 1.45), weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let artistName {
                Text(artistName)
                    .font(.system(size: max(21, fontSize * 0.88), weight: .semibold))
                    .foregroundStyle(LabTheme.chartChord)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, max(30, fontSize * 1.25))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var artistName: String? {
        preset.notes
            .components(separatedBy: .newlines)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.lowercased().hasPrefix("artista:") }
            .map { line in
                String(line.dropFirst("Artista:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    @ViewBuilder
    private func chartLine(_ line: ShowChartLine) -> some View {
        switch line.kind {
        case .section:
            Text(line.text)
                .font(.system(size: fontSize * 0.74, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, fontSize * 0.65)
                .padding(.bottom, fontSize * 0.18)
        case .chords:
            Text(line.text)
                .font(.system(size: fontSize * 0.82, weight: .semibold, design: .monospaced))
                .foregroundStyle(LabTheme.chartChord)
                .textSelection(.enabled)
                .padding(.bottom, 1)
        case .lyrics:
            Text(line.text)
                .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, fontSize * 0.26)
        case .space:
            Color.clear.frame(height: fontSize * 0.48)
        }
    }

    private func toneMetric(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: focusMode ? 28 : 25, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    private var chartKeyMetric: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TOM DA CIFRA")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 7) {
                chartTransposeButton(
                    semitones: -1,
                    systemImage: "minus",
                    label: "Baixar tom da cifra"
                )
                Picker("Tom da cifra", selection: chartKeyBinding) {
                    Section("Maior") {
                        ForEach(chartMajorKeys, id: \.self) { key in
                            Text(key).tag(key)
                        }
                    }
                    Section("Menor") {
                        ForEach(chartMinorKeys, id: \.self) { key in
                            Text(key).tag(key)
                        }
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(minWidth: focusMode ? 78 : 70)
                .help("Corrigir somente o nome do tom, sem alterar os acordes")
                .accessibilityLabel("Tom nominal da cifra")
                chartTransposeButton(
                    semitones: 1,
                    systemImage: "plus",
                    label: "Aumentar tom da cifra"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private var transposeMetric: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TRANSPOSE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 7) {
                transposeButton(
                    semitones: -1,
                    systemImage: "minus",
                    label: "Baixar transpose"
                )
                Text(signedSemitones(preset.transposeSemitones))
                    .font(.system(size: focusMode ? 28 : 25, weight: .bold, design: .monospaced))
                    .foregroundStyle(LabTheme.chartChord)
                    .frame(minWidth: focusMode ? 44 : 38)
                    .accessibilityLabel("Transpose \(signedSemitones(preset.transposeSemitones))")
                transposeButton(
                    semitones: 1,
                    systemImage: "plus",
                    label: "Aumentar transpose"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private var chartKeyBinding: Binding<String> {
        Binding(
            get: { preset.originalKey },
            set: { onSetChartKey($0) }
        )
    }

    private var chartMajorKeys: [String] {
        ["C", "C#", "Db", "D", "D#", "Eb", "E", "F", "F#", "Gb", "G", "G#", "Ab", "A", "A#", "Bb", "B"]
    }

    private var chartMinorKeys: [String] {
        chartMajorKeys.map { "\($0)m" }
    }

    private func chartTransposeButton(semitones: Int, systemImage: String, label: String) -> some View {
        let targetKey = ShowMusicTheory.transposedKey(preset.originalKey, by: semitones)
        return Button {
            onTransposeChart(semitones)
        } label: {
            Image(systemName: systemImage)
                .frame(width: focusMode ? 24 : 20, height: focusMode ? 24 : 20)
        }
        .buttonStyle(.bordered)
        .controlSize(focusMode ? .regular : .small)
        .disabled(targetKey == nil)
        .help(targetKey.map { "\(label): \(preset.originalKey) → \($0)" } ?? label)
        .accessibilityLabel(label)
    }

    private func transposeButton(semitones: Int, systemImage: String, label: String) -> some View {
        let target = preset.transposeSemitones + semitones
        return Button {
            onAdjustTranspose(semitones)
        } label: {
            Image(systemName: systemImage)
                .frame(width: focusMode ? 24 : 20, height: focusMode ? 24 : 20)
        }
        .buttonStyle(.bordered)
        .controlSize(focusMode ? .regular : .small)
        .disabled(!(-12...12).contains(target))
        .help("\(label): \(signedSemitones(preset.transposeSemitones)) → \(signedSemitones(target))")
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var stageControls: some View {
        if focusMode {
            HStack(alignment: .bottom, spacing: 16) {
                HStack(spacing: 9) {
                    songNavigationButton(
                        title: "Música anterior",
                        shortcut: "←",
                        systemImage: "backward.end.fill",
                        disabled: !canGoPrevious,
                        action: onPrevious
                    )

                    songNavigationButton(
                        title: "Próxima música",
                        shortcut: "→",
                        systemImage: "forward.end.fill",
                        disabled: !canGoNext,
                        action: onNext
                    )
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                Spacer(minLength: 8)

                speedControl
            }
        } else {
            HStack(spacing: 7) {
                Button(action: onPrevious) { Image(systemName: "backward.end.fill") }
                    .disabled(!canGoPrevious)
                    .help("Música anterior")
                autoScrollButton
                Button(action: onNext) { Image(systemName: "forward.end.fill") }
                    .disabled(!canGoNext)
                    .help("Próxima música")
            }
            .padding(7)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var autoScrollButton: some View {
        Button(action: toggleAutoScroll) {
            if focusMode {
                VStack(spacing: 2) {
                    Label(
                        autoScrollEnabled ? "Pausar" : "Iniciar",
                        systemImage: autoScrollEnabled ? "pause.fill" : "play.fill"
                    )
                    .font(.callout.weight(.semibold))
                    Text("Espaço")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 42)
            } else {
                Image(systemName: autoScrollEnabled ? "pause.fill" : "play.fill")
            }
        }
        .help(autoScrollEnabled ? "Pausar rolagem automática" : "Iniciar rolagem automática")
        .accessibilityHint("Atalho: Espaço ou P")
        .disabled(visibleLines.count < 2)
    }

    private var speedControl: some View {
        HStack(spacing: 10) {
            Button(action: toggleAutoScroll) {
                Image(systemName: autoScrollEnabled ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(autoScrollEnabled ? LabTheme.signal : Color.primary)
                    .frame(width: 38, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(autoScrollEnabled ? "Pausar rolagem (Espaço)" : "Iniciar rolagem (Espaço)")
            .accessibilityLabel(autoScrollEnabled ? "Pausar rolagem automática" : "Iniciar rolagem automática")
            .accessibilityHint("Atalho: Espaço")
            .disabled(visibleLines.count < 2)

            Divider().frame(height: 46)

            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Velocidade")
                        .foregroundStyle(.secondary)
                    Text("\(speedPosition)/5 · \(autoScrollSpeed.accessibilityName)")
                        .fontWeight(.semibold)
                        .contentTransition(.numericText())
                }
                .font(.caption)

                ZStack {
                    Capsule()
                        .fill(.secondary.opacity(0.55))
                        .frame(height: 2)
                        .padding(.horizontal, 9)

                    HStack(spacing: 0) {
                        ForEach(Array(ShowAutoScrollSpeed.allCases.enumerated()), id: \.element.id) { index, speed in
                            Button {
                                autoScrollSpeed = speed
                            } label: {
                                VStack(spacing: 0) {
                                    Rectangle()
                                        .fill(speed == autoScrollSpeed ? LabTheme.signal : Color.secondary)
                                        .frame(width: speed == autoScrollSpeed ? 3 : 2, height: speed == autoScrollSpeed ? 18 : 12)
                                    Circle()
                                        .fill(speed == autoScrollSpeed ? LabTheme.signal : Color.clear)
                                        .frame(width: 7, height: 7)
                                }
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Velocidade \(index + 1): \(speed.accessibilityName)")
                            .accessibilityLabel("Velocidade \(index + 1) de 5, \(speed.accessibilityName)")
                            .accessibilityAddTraits(speed == autoScrollSpeed ? .isSelected : [])
                        }
                    }
                }
                .frame(width: 210, height: 28)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Velocidade da rolagem automática")
        .accessibilityValue("\(autoScrollSpeed.accessibilityName), \(speedPosition) de 5")
    }

    private var speedPosition: Int {
        (ShowAutoScrollSpeed.allCases.firstIndex(of: autoScrollSpeed) ?? 0) + 1
    }

    private func songNavigationButton(
        title: String,
        shortcut: String,
        systemImage: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            stopAutoScroll()
            action()
        } label: {
            VStack(spacing: 2) {
                Label(title, systemImage: systemImage)
                    .font(.callout.weight(.semibold))
                Text(shortcut)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 42)
        }
        .disabled(disabled)
        .help(title)
        .accessibilityHint("Atalho: \(shortcut)")
    }

    private func toggleAutoScroll() {
        if autoScrollEnabled {
            stopAutoScroll()
        } else {
            autoScrollEnabled = true
        }
    }

    private func startAutoScroll() {
        guard visibleLines.count >= 2 else {
            autoScrollEnabled = false
            return
        }
        autoScrollEnabled = true
        scrollDriver.start(pointsPerSecond: autoScrollSpeed.pointsPerSecond) {
            autoScrollEnabled = false
        }
    }

    private func stopAutoScroll() {
        scrollDriver.stop()
        autoScrollEnabled = false
    }

    private func lines(showingChords: Bool) -> [ShowChartLine] {
        allLines.filter { showingChords || $0.kind != .chords }
    }

    private var chordVisibilityBinding: Binding<Bool> {
        Binding(
            get: { showChords },
            set: { newValue in
                guard newValue != showChords else { return }
                let wasAtDocumentHeader = focusMode && position == 0
                let currentLines = lines(showingChords: showChords)
                let currentLineIndex = max(0, position - (focusMode ? 1 : 0))
                let anchorID = currentLines.indices.contains(currentLineIndex) ? currentLines[currentLineIndex].id : nil
                let sourceAnchor = anchorID.flatMap { id in allLines.firstIndex(where: { $0.id == id }) } ?? 0

                showChords = newValue
                if wasAtDocumentHeader {
                    position = 0
                    return
                }
                let updatedLines = lines(showingChords: newValue)
                if let anchorID,
                   let exactIndex = updatedLines.firstIndex(where: { $0.id == anchorID }) {
                    position = exactIndex + (focusMode ? 1 : 0)
                    return
                }

                let nearest = updatedLines.enumerated().min { lhs, rhs in
                    let lhsSource = allLines.firstIndex(where: { $0.id == lhs.element.id }) ?? 0
                    let rhsSource = allLines.firstIndex(where: { $0.id == rhs.element.id }) ?? 0
                    return Swift.abs(lhsSource - sourceAnchor) < Swift.abs(rhsSource - sourceAnchor)
                }
                position = (nearest?.offset ?? 0) + (focusMode ? 1 : 0)
            }
        )
    }

    private var applyHelp: String {
        if !isConnected { return "Conecte o PA700 para aplicar esta configuração" }
        if !preset.isReadyToPlay { return "Finalize a configuração em Editar música" }
        if editingAnnotations { return "Conclua a edição das anotações antes de aplicar" }
        if editingChart { return "Salve ou cancele o rascunho antes de aplicar" }
        return focusMode
            ? "Enviar esta configuração ao PA700 · Enter"
            : "Enviar esta configuração ao PA700 · ⌘ Enter"
    }

    @ViewBuilder
    private var applicationButton: some View {
        let button = Button(applyButtonTitle, systemImage: applyButtonIcon, action: onApply)
            .tint(isConnected ? applyButtonTint : .gray)
            .disabled(!isConnected || !preset.isReadyToPlay || isEditingContent)
            .keyboardShortcut(.return, modifiers: [.command])
            .help(applyHelp)
        if applicationState == .current {
            button.buttonStyle(.bordered)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    private var applicationBadge: String {
        switch applicationState {
        case .notApplied: return "SOMENTE LEITURA"
        case .current: return "APLICADA PELO APP"
        case .stale: return "ÚLTIMO ENVIO"
        }
    }

    private var applicationBadgeIcon: String {
        switch applicationState {
        case .notApplied: return "doc.text.fill"
        case .current: return "paperplane.circle.fill"
        case .stale: return "clock.arrow.circlepath"
        }
    }

    private var applicationBadgeColor: Color {
        switch applicationState {
        case .notApplied, .stale: return LabTheme.draft
        case .current: return LabTheme.signal
        }
    }

    private var applyButtonTitle: String {
        switch applicationState {
        case .notApplied: return "Aplicar no PA700"
        case .current: return "Reaplicar"
        case .stale: return "Sincronizar PA700"
        }
    }

    private var applyButtonIcon: String {
        applicationState == .stale ? "arrow.triangle.2.circlepath" : "paperplane.fill"
    }

    private var applyButtonTint: Color {
        applicationState == .stale ? LabTheme.draft : LabTheme.signal
    }

    private var isEditingContent: Bool {
        editingAnnotations || editingChart
    }

    private var chartDraftEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Rascunho local", systemImage: "pencil.and.list.clipboard")
                    .font(.headline)
                Spacer()
                Text("Nada será enviado ao PA700")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LabTheme.draft)
            }
            Text("Use # antes de uma seção, > antes de uma linha de acordes e texto normal para a letra.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $chartDraftText)
                .font(.system(size: max(17, fontSize * 0.78), design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: LabTheme.radius))
                .overlay {
                    RoundedRectangle(cornerRadius: LabTheme.radius)
                        .stroke(LabTheme.signal.opacity(0.55), lineWidth: 1)
                }
                .accessibilityLabel("Editor do rascunho da cifra")
        }
        .padding(.horizontal, focusMode ? 28 : 22)
        .padding(.vertical, focusMode ? 22 : 18)
    }

    private func beginChartDraft() {
        editingAnnotations = false
        chartDraftText = ShowChartLine.editorText(from: preset.chartLines)
        editingChart = true
    }

    private func cancelChartDraft() {
        chartDraftText = ""
        editingChart = false
    }

    private func saveChartDraft() {
        guard onSaveChartDraft(chartDraftText) else { return }
        chartDraftText = ""
        editingChart = false
        position = 0
    }

    private func addAnnotation() {
        let step = Double(annotations.count % 5) * 0.12
        annotations.append(.init(normalizedX: 0.77, normalizedY: min(0.76, 0.18 + step)))
    }

    private func deleteAnnotation(_ id: UUID) {
        annotations.removeAll { $0.id == id }
    }

    private var visibleLineIDBinding: Binding<UUID?> {
        Binding(
            get: {
                if focusMode, position == 0 { return preset.id }
                let lineIndex = position - (focusMode ? 1 : 0)
                return visibleLines.indices.contains(lineIndex) ? visibleLines[lineIndex].id : visibleLines.first?.id
            },
            set: { lineID in
                if focusMode, lineID == preset.id {
                    position = 0
                    return
                }
                guard let lineID, let index = visibleLines.firstIndex(where: { $0.id == lineID }) else { return }
                position = index + (focusMode ? 1 : 0)
            }
        )
    }
}

private func signedSemitones(_ value: Int) -> String {
    value == 0 ? "0" : "\(value > 0 ? "+" : "")\(value)"
}

@MainActor
private final class ShowContinuousScrollDriver: ObservableObject {
    private weak var scrollView: NSScrollView?
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var pointsPerSecond: CGFloat = ShowAutoScrollSpeed.normal.pointsPerSecond
    private var onReachEnd: (() -> Void)?
    private var wantsToRun = false

    func attach(to scrollView: NSScrollView) {
        guard self.scrollView !== scrollView else { return }
        self.scrollView = scrollView
        if wantsToRun { beginTimer() }
    }

    func start(pointsPerSecond: CGFloat, onReachEnd: @escaping () -> Void) {
        self.pointsPerSecond = pointsPerSecond
        self.onReachEnd = onReachEnd
        wantsToRun = true
        guard scrollView != nil else { return }
        if isAtEnd { scrollToTop() }
        beginTimer()
    }

    func updateSpeed(_ pointsPerSecond: CGFloat) {
        self.pointsPerSecond = pointsPerSecond
    }

    func stop() {
        wantsToRun = false
        timer?.invalidate()
        timer = nil
    }

    private func beginTimer() {
        timer?.invalidate()
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard wantsToRun, let scrollView, let documentView = scrollView.documentView else {
            stop()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(0.05, max(0, now - lastTick))
        lastTick = now

        let clipView = scrollView.contentView
        let maximumY = max(0, documentView.bounds.height - clipView.bounds.height)
        guard maximumY > 0 else { return }
        let nextY = min(maximumY, clipView.bounds.origin.y + pointsPerSecond * elapsed)
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: nextY))
        scrollView.reflectScrolledClipView(clipView)

        if nextY >= maximumY - 0.5 {
            let completion = onReachEnd
            stop()
            completion?()
        }
    }

    private var isAtEnd: Bool {
        guard let scrollView, let documentView = scrollView.documentView else { return false }
        let maximumY = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
        return maximumY > 0 && scrollView.contentView.bounds.origin.y >= maximumY - 0.5
    }

    private func scrollToTop() {
        guard let scrollView else { return }
        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: 0))
        scrollView.reflectScrolledClipView(clipView)
    }
}

private struct ShowScrollViewResolver: NSViewRepresentable {
    let driver: ShowContinuousScrollDriver

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        resolve(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        resolve(from: nsView)
    }

    private func resolve(from view: NSView) {
        DispatchQueue.main.async {
            var ancestor = view.superview
            while let current = ancestor {
                if let scrollView = current as? NSScrollView {
                    driver.attach(to: scrollView)
                    return
                }
                ancestor = current.superview
            }
        }
    }
}

private struct ShowAnnotationNote: View {
    @Binding var annotation: ShowChartAnnotation
    let canvasSize: CGSize
    let isEditing: Bool
    let onDelete: () -> Void
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                Text("Arraste")
                    .font(.caption2.weight(.bold))
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LabTheme.annotationInk.opacity(0.68))
                }
                .buttonStyle(.plain)
                .help("Apagar anotação")
                .accessibilityLabel("Apagar anotação")
            }
            .foregroundStyle(LabTheme.annotationInk.opacity(0.62))
            .padding(.horizontal, 8)
            .frame(height: 27)
            .contentShape(Rectangle())
            .gesture(dragGesture)

            Group {
                if isEditing {
                    TextEditor(text: $annotation.text)
                        .font(.system(size: 17, weight: .semibold))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(LabTheme.annotationInk)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 5)
                } else {
                    Text(annotation.text)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(LabTheme.annotationInk)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(width: 224, height: 100)
        .background(LabTheme.annotation)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isEditing ? LabTheme.signal : LabTheme.annotationInk.opacity(0.22), lineWidth: isEditing ? 2 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .position(notePosition)
        .offset(dragOffset)
        .accessibilityLabel("Anotação: \(annotation.text)")
        .accessibilityAction(named: "Mover para cima") { moveAnnotation(dx: 0, dy: -0.05) }
        .accessibilityAction(named: "Mover para baixo") { moveAnnotation(dx: 0, dy: 0.05) }
        .accessibilityAction(named: "Mover para a esquerda") { moveAnnotation(dx: -0.05, dy: 0) }
        .accessibilityAction(named: "Mover para a direita") { moveAnnotation(dx: 0.05, dy: 0) }
    }

    private var notePosition: CGPoint {
        CGPoint(
            x: min(max(116, canvasSize.width * annotation.normalizedX), max(116, canvasSize.width - 116)),
            y: min(max(54, canvasSize.height * annotation.normalizedY), max(54, canvasSize.height - 54))
        )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($dragOffset) { value, state, transaction in
                transaction.animation = nil
                state = value.translation
            }
            .onEnded { value in
                guard canvasSize.width > 0, canvasSize.height > 0 else { return }
                annotation.normalizedX = min(0.92, max(0.08, (notePosition.x + value.translation.width) / canvasSize.width))
                annotation.normalizedY = min(0.92, max(0.08, (notePosition.y + value.translation.height) / canvasSize.height))
            }
    }

    private func moveAnnotation(dx: Double, dy: Double) {
        annotation.normalizedX = min(0.92, max(0.08, annotation.normalizedX + dx))
        annotation.normalizedY = min(0.92, max(0.08, annotation.normalizedY + dy))
    }
}

private struct ShowKeyboardMonitor: NSViewRepresentable {
    let enabled: Bool
    let performanceMode: Bool
    let onAction: (ShowPerformanceKeyAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        context.coordinator.update(enabled: enabled, performanceMode: performanceMode, onAction: onAction)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.update(enabled: enabled, performanceMode: performanceMode, onAction: onAction)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private weak var view: NSView?
        private var enabled = false
        private var performanceMode = false
        private var onAction: ((ShowPerformanceKeyAction) -> Void)?
        private var monitor: Any?

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.enabled,
                      let window = self.view?.window,
                      event.windowNumber == window.windowNumber else { return event }

                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                if event.keyCode == 49, modifiers.isEmpty {
                    guard !event.isARepeat else { return nil }
                    self.onAction?(.toggleAutoScroll)
                    return nil
                }
                if event.keyCode == 49, modifiers == .shift {
                    self.onAction?(.page(-8))
                    return nil
                }
                guard self.performanceMode, !modifiers.contains(.command),
                      !modifiers.contains(.control), !modifiers.contains(.option) else { return event }
                let action: ShowPerformanceKeyAction?
                switch event.keyCode {
                case 36: action = .applyCurrentPreset // Return
                case 35: action = .toggleAutoScroll // P
                case 123: action = .previousSong
                case 124: action = .nextSong
                case 126: action = .page(-8)
                case 125: action = .page(8)
                case 27, 78: action = .adjustSpeed(-1) // – or keypad –
                case 24, 69: action = .adjustSpeed(1) // +/= or keypad +
                case 115: action = .top
                case 4: action = .toggleChrome // H
                default: action = nil
                }
                guard let action else { return event }
                if event.isARepeat,
                   event.keyCode != 49, event.keyCode != 125, event.keyCode != 126 { return nil }
                self.onAction?(action)
                return nil
            }
        }

        func update(
            enabled: Bool,
            performanceMode: Bool,
            onAction: @escaping (ShowPerformanceKeyAction) -> Void
        ) {
            self.enabled = enabled
            self.performanceMode = performanceMode
            self.onAction = onAction
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            stop()
        }
    }
}

private struct ShowMouseMovementMonitor: NSViewRepresentable {
    let enabled: Bool
    let onTopEdgeChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        context.coordinator.update(enabled: enabled, onTopEdgeChange: onTopEdgeChange)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.update(enabled: enabled, onTopEdgeChange: onTopEdgeChange)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private weak var view: NSView?
        private var enabled = false
        private var onTopEdgeChange: ((Bool) -> Void)?
        private var wasAtTopEdge = false
        private var monitor: Any?

        func attach(to view: NSView) {
            self.view = view
            DispatchQueue.main.async { [weak view] in
                view?.window?.acceptsMouseMovedEvents = true
            }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
            ) { [weak self] event in
                guard let self,
                      self.enabled,
                      let window = self.view?.window,
                      event.windowNumber == window.windowNumber else { return event }
                let isAtTopEdge = event.locationInWindow.y >= window.contentLayoutRect.maxY - 88
                guard isAtTopEdge != self.wasAtTopEdge else { return event }
                self.wasAtTopEdge = isAtTopEdge
                self.onTopEdgeChange?(isAtTopEdge)
                return event
            }
        }

        func update(enabled: Bool, onTopEdgeChange: @escaping (Bool) -> Void) {
            self.enabled = enabled
            self.onTopEdgeChange = onTopEdgeChange
            if !enabled { wasAtTopEdge = false }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit { stop() }
    }
}

private struct ShowPA700LiveStateStrip: View {
    let state: PA700LiveState
    let commandedState: PA700CommandedShowState?
    let commandedSummary: String?
    let isConnected: Bool

    private var comparison: PA700LiveComparison {
        PA700LiveComparator.compare(
            state: state,
            expected: commandedState?.status == .current ? commandedState?.preset : nil
        )
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                statusLabel
                if let commandedState, let commandedSummary {
                    Divider().frame(height: 18)
                    provenanceMetric(
                        commandedState.status == .current ? "Aplicado pelo app" : "Último aplicado",
                        commandedSummary,
                        color: commandedState.status == .current ? LabTheme.signal : .secondary
                    )
                }
                if state.hasCurrentIdentifier {
                    Divider().frame(height: 18)
                    provenanceMetric("Observado no PA700", currentObservedSummary, color: .primary)
                } else if state.hasStaleIdentifier {
                    Divider().frame(height: 18)
                    provenanceMetric("Último observado", staleObservedSummary, color: .secondary)
                } else if commandedState == nil {
                    Divider().frame(height: 18)
                    Text(isConnected ? "Estado atual não consultável pelo PA700" : "Nenhum estado musical disponível")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                statusLabel
                Divider().frame(height: 18)
                Text(compactSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 38)
        .background(LabTheme.stageSurface)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .help(accessibilitySummary)
    }

    private var statusLabel: some View {
        Label(statusText, systemImage: statusIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)
            .fixedSize()
    }

    private func provenanceMetric(_ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(color)
                .fontWeight(.semibold)
        }
        .font(.caption.monospacedDigit())
        .fixedSize()
    }

    private var statusText: String {
        guard isConnected else { return "KORG desconectado" }
        switch comparison.status {
        case .matches:
            return comparison.inferredFields.isEmpty
                ? "KORG confere"
                : "Compatível, falta confirmar \(comparison.inferredFields.joined(separator: ", "))"
        case .mismatch: return "Diverge: \(comparison.mismatchedFields.joined(separator: ", "))"
        case .unknown:
            if commandedState?.status == .current { return "Aplicado pelo app" }
            if state.hasCurrentIdentifier { return "Observado no PA700" }
            if commandedState != nil || state.hasStaleIdentifier { return "Último estado conhecido" }
            return "KORG conectado"
        }
    }

    private var statusIcon: String {
        guard isConnected else { return "circle.dashed" }
        switch comparison.status {
        case .matches: return "checkmark.circle.fill"
        case .mismatch: return "exclamationmark.triangle.fill"
        case .unknown:
            if commandedState?.status == .current { return "paperplane.circle.fill" }
            if state.hasCurrentIdentifier { return "waveform.path.ecg" }
            if commandedState != nil || state.hasStaleIdentifier { return "clock.arrow.circlepath" }
            return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        guard isConnected else { return .secondary }
        switch comparison.status {
        case .matches: return comparison.inferredFields.isEmpty ? LabTheme.verified : LabTheme.draft
        case .mismatch: return LabTheme.draft
        case .unknown:
            if commandedState?.status == .current { return LabTheme.signal }
            if state.hasCurrentIdentifier { return LabTheme.inbound }
            if commandedState != nil || state.hasStaleIdentifier { return .secondary }
            return LabTheme.verified
        }
    }

    private var currentObservedSummary: String {
        var values: [String] = []
        if let style = state.style.currentValue { values.append("Style \(style.displayName)\(state.style.certainty == .inferred ? "?" : "")") }
        if let slot = state.keyboardSetSlot.currentValue { values.append("Kbd \(slot)") }
        if let transpose = state.transpose.currentValue { values.append("T \(transpose > 0 ? "+" : "")\(transpose)") }
        if let songBook = state.songBookEntry.currentValue { values.append("SB \(songBook)") }
        appendPartSounds(to: &values, certainty: { $0.isCurrent })
        return values.isEmpty ? "Nenhum estado musical recebido" : values.joined(separator: " · ")
    }

    private var staleObservedSummary: String {
        var values: [String] = []
        if state.style.certainty == .stale, let style = state.style.value { values.append("Style \(style.displayName)") }
        if state.keyboardSetSlot.certainty == .stale, let slot = state.keyboardSetSlot.value { values.append("Kbd \(slot)") }
        if state.transpose.certainty == .stale, let transpose = state.transpose.value {
            values.append("T \(transpose > 0 ? "+" : "")\(transpose)")
        }
        if state.songBookEntry.certainty == .stale, let songBook = state.songBookEntry.value { values.append("SB \(songBook)") }
        appendPartSounds(to: &values, certainty: { $0 == .stale })
        return values.isEmpty ? "Nenhum estado musical anterior" : values.joined(separator: " · ")
    }

    private func appendPartSounds(
        to values: inout [String],
        certainty predicate: (PA700LiveCertainty) -> Bool
    ) {
        for (part, label) in [
            (ShowKeyboardPart.upper1, "U1"),
            (.upper2, "U2"),
            (.upper3, "U3"),
            (.lower, "L")
        ] {
            guard let sound = state.parts[part]?.sound,
                  predicate(sound.certainty),
                  let selection = sound.value else { continue }
            values.append("\(label) \(selection.displayName)")
        }
    }

    private var compactSummary: String {
        if state.hasCurrentIdentifier { return currentObservedSummary }
        if commandedState?.status == .current { return "Aplicado: \(commandedSummary ?? "configuração enviada")" }
        if state.hasStaleIdentifier { return "Último observado: \(staleObservedSummary)" }
        if commandedState != nil { return "Último aplicado: \(commandedSummary ?? "configuração enviada")" }
        return isConnected ? "Estado atual não consultável pelo PA700" : "Nenhum estado musical disponível"
    }

    private var accessibilitySummary: String {
        var summary = statusText + "."
        if let commandedState, let commandedSummary {
            summary += " \(commandedState.status == .current ? "Aplicado pelo aplicativo" : "Último estado aplicado"): \(commandedSummary)."
        }
        if state.hasCurrentIdentifier {
            summary += " Observado no PA700: \(currentObservedSummary)."
        } else if state.hasStaleIdentifier {
            summary += " Último estado observado: \(staleObservedSummary)."
        } else if commandedState == nil {
            summary += isConnected
                ? " O PA700 não disponibiliza uma consulta do estado musical atual."
                : " Nenhum estado musical está disponível."
        }
        if state.style.certainty == .inferred { summary += " Style inferido, ainda não confirmado fisicamente." }
        if let source = state.transpose.source, state.transpose.certainty.isCurrent { summary += " Transpose: \(source)." }
        return summary
    }
}

private struct ShowConnectionStrip: View {
    @EnvironmentObject private var model: AppModel
    let workspaceMode: ShowWorkspaceMode
    let focusMode: Bool
    let onSelectWorkspaceMode: (ShowWorkspaceMode) -> Void
    let onToggleFocus: () -> Void
    let onFullScreen: () -> Void
    @State private var connectionIndicatorHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.resetPA700Connection()
            } label: {
                Group {
                    if model.pa700ConnectionHealth == .reconnecting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(LabTheme.draft)
                    } else {
                        Image(systemName: connectionIndicatorHovered ? "arrow.clockwise.circle" : connectionIndicatorIcon)
                            .foregroundStyle(connectionIndicatorColor)
                    }
                }
                .frame(width: 22, height: 22)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.pa700ConnectionHealth == .reconnecting)
            .accessibilityLabel(connectionButtonLabel)
            .help(connectionButtonLabel)
            .onHover { connectionIndicatorHovered = $0 }
            VStack(alignment: .leading, spacing: 1) {
                Text(connectionTitle)
                    .fontWeight(.semibold)
                Text(connectionSubtitle)
                    .font(.caption)
                    .foregroundStyle(model.pa700ConnectionHealth == .unresponsive ? LabTheme.danger : Color.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Picker("Workspace", selection: Binding(get: { workspaceMode }, set: onSelectWorkspaceMode)) {
                ForEach(ShowWorkspaceMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
            .accessibilityLabel("Modo do workspace")
            if workspaceMode == .show {
                Button(focusMode ? "Sair do foco" : "Foco", systemImage: focusMode ? "rectangle.compress.vertical" : "rectangle.expand.vertical", action: onToggleFocus)
                    .help(focusMode ? "Mostrar repertório e detalhes" : "Deixar somente a cifra e os controles de palco")
                Button("Tela cheia", systemImage: "arrow.up.left.and.arrow.down.right", action: onFullScreen)
                    .help("Usar o monitor inteiro para o show")
            }
            Button("Panic", systemImage: "exclamationmark.octagon.fill") { model.panic() }
                .buttonStyle(.borderedProminent)
                .tint(LabTheme.danger)
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .help("Silenciar imediatamente todas as notas")
        }
        .controlSize(focusMode ? .large : .regular)
        .padding(.horizontal, 20)
        .frame(height: LabTheme.statusStripHeight)
        .background(LabTheme.stageSurface)
    }

    private var connectionIndicatorIcon: String {
        switch model.pa700ConnectionHealth {
        case .confirmed: "circle.fill"
        case .unresponsive: "exclamationmark.circle.fill"
        case .disconnected, .reconnecting: "circle"
        }
    }

    private var connectionIndicatorColor: Color {
        switch model.pa700ConnectionHealth {
        case .confirmed: LabTheme.verified
        case .unresponsive: LabTheme.danger
        case .reconnecting: LabTheme.draft
        case .disconnected: .secondary
        }
    }

    private var connectionButtonLabel: String {
        switch model.pa700ConnectionHealth {
        case .confirmed: "Reconectar PA700"
        case .reconnecting: "Reconectando PA700"
        case .disconnected, .unresponsive: "Tentar conectar PA700"
        }
    }

    private var connectionTitle: String {
        switch model.pa700ConnectionHealth {
        case .confirmed: "PA700 conectado via USB"
        case .reconnecting: "Reconectando ao PA700"
        case .unresponsive: "PA700 sem resposta"
        case .disconnected: "Nenhum teclado conectado"
        }
    }

    private var connectionSubtitle: String {
        switch model.pa700ConnectionHealth {
        case .confirmed: model.showStatus
        case .reconnecting: "Verificando a conexão MIDI…"
        case .unresponsive: model.showStatus
        case .disconnected: "Reconecte o USB para liberar as músicas confirmadas"
        }
    }
}
