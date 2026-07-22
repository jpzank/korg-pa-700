import ArrangerLabCore
import AppKit
import SwiftUI

struct ShowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @FocusState private var focusedItemID: UUID?
    @AppStorage("arrangerlab.showReaderFontSize") private var readerFontSize = 23.0
    @AppStorage("arrangerlab.showFocusReaderFontSize") private var focusReaderFontSize = 29.0
    @AppStorage("arrangerlab.showReaderChords") private var showChords = true
    @State private var chartPositions: [UUID: Int] = [:]
    @State private var readingItemID: UUID?
    @State private var focusMode = false
    @State private var editingAnnotations = false

    var body: some View {
        VStack(spacing: 0) {
            ShowConnectionStrip(
                focusMode: focusMode,
                onToggleFocus: toggleFocusMode,
                onFullScreen: enterFullScreen
            )
            Divider()

            if let setList = model.activeShowSetList {
                showContent(setList)
            } else {
                emptyState
            }
        }
        .tint(LabTheme.signal)
        .preferredColorScheme(.dark)
        .background {
            ShowKeyboardMonitor(enabled: !editingAnnotations) { amount in
                pageReadingChart(by: amount)
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
        .onAppear {
            selectCurrentOrFirstItem()
            loadReaderDefaults()
        }
        .onChange(of: model.activeShowSetListID) { _, _ in selectCurrentOrFirstItem() }
        .onChange(of: model.activeShowSetListItemID) { _, newValue in
            if let newValue {
                focusedItemID = newValue
                readingItemID = newValue
            }
        }
        .onChange(of: readingItemID) { _, _ in loadReaderDefaults() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            focusMode = false
            editingAnnotations = false
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

                    if geometry.size.width >= 1_180 {
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
                    Text("Adicione músicas em Preparar show.")
                        .foregroundStyle(.secondary)
                    Button("Preparar repertório", systemImage: "slider.horizontal.3") {
                        openWindow(id: "prepare-show")
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(setList.items.enumerated()), id: \.element.id) { index, item in
                                showRow(index: index, item: item)
                                    .id(item.id)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onChange(of: focusedItemID) { _, itemID in
                        if let itemID { proxy.scrollTo(itemID, anchor: .center) }
                    }
                    .onMoveCommand { direction in moveFocus(direction, in: setList) }
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

    private func showRow(index: Int, item: ShowSetListItem) -> some View {
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
            guard let preset else { return }
            focusedItemID = item.id
            readingItemID = item.id
            model.openShowPresetForReading(preset)
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
    }

    private func chartStage(_ preset: ShowPreset?, setList: ShowSetList) -> some View {
        Group {
            if let preset {
                ShowChartReader(
                    preset: preset,
                    isApplied: isReadingApplied,
                    isConnected: model.connected,
                    focusMode: focusMode,
                    showChords: $showChords,
                    fontSize: activeReaderFontSize,
                    editingAnnotations: $editingAnnotations,
                    annotations: annotationBinding(for: preset),
                    position: Binding(
                        get: { chartPositions[preset.id] ?? 0 },
                        set: { chartPositions[preset.id] = $0 }
                    ),
                    progressText: progressText(in: setList),
                    nextTitle: nextPreset(in: setList)?.songTitle,
                    canGoPrevious: canNavigate(by: -1, in: setList),
                    canGoNext: canNavigate(by: 1, in: setList),
                    onPrevious: { navigate(by: -1, in: setList) },
                    onNext: { navigate(by: 1, in: setList) },
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
            Text(displayedPreset.map { _ in isReadingApplied ? "NO PA700" : "EM LEITURA" } ?? "MÚSICA")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            if let preset = displayedPreset {
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
                    if !isReadingApplied {
                        Label("Não enviada ao PA700", systemImage: "doc.text")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LabTheme.draft)
                    }
                }

                Divider()

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

            if let active = model.activeShowPreset,
               !isReadingApplied {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("TOCANDO NO PA700")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LabTheme.verified)
                    Text(active.songTitle)
                        .font(.headline)
                        .lineLimit(2)
                    Text("\(setupLabel(active)) · \(transposeText(active.transposeSemitones))")
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

    private func loadReaderDefaults() {
        guard let setList = model.activeShowSetList,
              let preset = readingPreset(in: setList) else { return }
        showChords = preset.readerSettings.showChords
        readerFontSize = min(37, max(17, 23 * preset.readerSettings.fontScale))
    }

    private func moveFocus(_ direction: MoveCommandDirection, in setList: ShowSetList) {
        guard !setList.items.isEmpty else { return }
        let currentIndex = focusedItemID.flatMap { id in setList.items.firstIndex(where: { $0.id == id }) } ?? 0
        let nextIndex: Int
        switch direction {
        case .up: nextIndex = max(0, currentIndex - 1)
        case .down: nextIndex = min(setList.items.count - 1, currentIndex + 1)
        default: return
        }
        let item = setList.items[nextIndex]
        focusedItemID = item.id
        readingItemID = item.id
        if item.id != model.activeShowSetListItemID,
           let preset = model.showPreset(for: item) {
            model.openShowPresetForReading(preset)
        }
    }

    private func navigate(by offset: Int, in setList: ShowSetList) {
        guard let referenceID = readingItemID ?? model.activeShowSetListItemID,
              let index = setList.items.firstIndex(where: { $0.id == referenceID }) else { return }
        let destination = index + offset
        guard setList.items.indices.contains(destination) else { return }
        let item = setList.items[destination]
        focusedItemID = item.id
        readingItemID = item.id
        editingAnnotations = false
        if let preset = model.showPreset(for: item) {
            model.openShowPresetForReading(preset)
        }
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
            max(0, visibleLineCount - 1)
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
        editingAnnotations = false
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    private func toggleFocusMode() {
        editingAnnotations = false
        focusMode.toggle()
    }

    private var activeReaderFontSize: Binding<Double> {
        focusMode ? $focusReaderFontSize : $readerFontSize
    }

    private func readingPreset(in setList: ShowSetList) -> ShowPreset? {
        guard let itemID = readingItemID ?? model.activeShowSetListItemID,
              let item = setList.items.first(where: { $0.id == itemID }) else { return nil }
        return model.showPreset(for: item)
    }

    private var readingStatusIcon: String {
        guard readingItemID != nil else { return "circle.dashed" }
        return readingItemID == model.activeShowSetListItemID ? "checkmark.circle.fill" : "doc.text.fill"
    }

    private var readingStatusColor: Color {
        readingItemID == model.activeShowSetListItemID ? LabTheme.verified : LabTheme.signal
    }

    private var isReadingApplied: Bool {
        guard let readingItemID else { return false }
        return readingItemID == model.activeShowSetListItemID
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
            let sound = preset.parts.first(where: { $0.part == .upper1 })?.displayName ?? "Kbd \(preset.keyboardSetSlot ?? 0)"
            return "JPD · \(sound)"
        }
        return songBookLabel(preset.songBookNumber)
    }

    private func transposeText(_ value: Int) -> String {
        value == 0 ? "Transp. 0" : "Transp. \(value > 0 ? "+" : "")\(value)"
    }

    private func signedSemitones(_ value: Int) -> String {
        value == 0 ? "0" : "\(value > 0 ? "+" : "")\(value)"
    }

    private func soundingKey(_ preset: ShowPreset) -> String? {
        ShowMusicTheory.transposedKey(preset.originalKey, by: preset.transposeSemitones)
    }
}

private struct ShowChartReader: View {
    let preset: ShowPreset
    let isApplied: Bool
    let isConnected: Bool
    let focusMode: Bool
    @Binding var showChords: Bool
    @Binding var fontSize: Double
    @Binding var editingAnnotations: Bool
    @Binding var annotations: [ShowChartAnnotation]
    @Binding var position: Int
    let progressText: String
    let nextTitle: String?
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onApply: () -> Void

    private var allLines: [ShowChartLine] {
        ShowChartLine.removingImportArtifacts(from: preset.chartLines)
    }

    private var visibleLines: [ShowChartLine] {
        lines(showingChords: showChords)
    }

    var body: some View {
        VStack(spacing: 0) {
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
                            Label(isApplied ? "NO PA700" : "SOMENTE LEITURA", systemImage: isApplied ? "checkmark.circle.fill" : "doc.text.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(isApplied ? LabTheme.verified : LabTheme.draft)
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
                        .disabled(!canGoPrevious || editingAnnotations)
                        .keyboardShortcut(.leftArrow, modifiers: [.command])

                        Button(action: onNext) {
                            Label("Próxima", systemImage: "chevron.right")
                        }
                        .disabled(!canGoNext || editingAnnotations)
                        .keyboardShortcut(.rightArrow, modifiers: [.command])

                        if !isApplied {
                            Button("Aplicar no PA700", systemImage: "paperplane.fill", action: onApply)
                                .buttonStyle(.borderedProminent)
                                .tint(isConnected ? LabTheme.signal : .gray)
                                .disabled(!isConnected || !preset.isReadyToPlay || editingAnnotations)
                                .keyboardShortcut(.return, modifiers: [.command])
                                .help(applyHelp)
                        }
                    }
                    .controlSize(focusMode ? .large : .regular)
                }

                HStack(spacing: 8) {
                    HStack(spacing: 0) {
                        toneMetric(label: "MÃOS", value: preset.originalKey.isEmpty ? "?" : preset.originalKey, color: .primary)
                        Divider().frame(height: 34)
                        toneMetric(label: "TRANSPOSE", value: signedSemitones(preset.transposeSemitones), color: LabTheme.chartChord)
                        Divider().frame(height: 34)
                        toneMetric(
                            label: "SOA",
                            value: ShowMusicTheory.transposedKey(preset.originalKey, by: preset.transposeSemitones) ?? "?",
                            color: LabTheme.verified
                        )
                    }
                    .accessibilityElement(children: .combine)

                    Spacer(minLength: 8)

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
                .controlSize(focusMode ? .large : .regular)
            }
            .padding(.horizontal, focusMode ? 28 : 22)
            .padding(.vertical, focusMode ? 11 : 14)
            .background(LabTheme.stageSurface.opacity(0.92))

            Divider()

            if visibleLines.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("Cifra ainda não cadastrada")
                        .font(.headline)
                    Text("Abra Preparar show para editar o conteúdo desta música.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
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

                        pagingControls
                        .buttonStyle(.bordered)
                        .controlSize(focusMode ? .large : .regular)
                        .padding(focusMode ? 24 : 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .allowsHitTesting(!editingAnnotations)
                    }
                }
            }
        }
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
    }

    private func signedSemitones(_ value: Int) -> String {
        value == 0 ? "0" : "\(value > 0 ? "+" : "")\(value)"
    }

    private func move(by amount: Int) {
        position = min(max(0, position + amount), max(0, visibleLines.count - 1))
    }

    @ViewBuilder
    private var pagingControls: some View {
        if focusMode {
            HStack(spacing: 10) {
                pagingButton(
                    title: "Voltar",
                    shortcut: "⇧ Espaço",
                    systemImage: "chevron.up"
                ) { move(by: -8) }
                pagingButton(
                    title: "Avançar",
                    shortcut: "Espaço",
                    systemImage: "chevron.down"
                ) { move(by: 8) }
            }
        } else {
            VStack(spacing: 8) {
                pagingButton(
                    title: "Voltar uma tela",
                    shortcut: "Shift + Espaço",
                    systemImage: "chevron.up"
                ) { move(by: -8) }
                pagingButton(
                    title: "Avançar uma tela",
                    shortcut: "Espaço",
                    systemImage: "chevron.down"
                ) { move(by: 8) }
            }
        }
    }

    private func pagingButton(
        title: String,
        shortcut: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if focusMode {
                    VStack(spacing: 2) {
                        Label(title, systemImage: systemImage)
                            .font(.callout.weight(.semibold))
                        Text(shortcut)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 104, minHeight: 42)
                } else {
                    Image(systemName: systemImage)
                        .frame(width: 20, height: 20)
                }
            }
        }
        .help("\(title) (\(shortcut))")
        .accessibilityLabel(title)
        .accessibilityHint("Atalho: \(shortcut)")
    }

    private func lines(showingChords: Bool) -> [ShowChartLine] {
        allLines.filter { showingChords || $0.kind != .chords }
    }

    private var chordVisibilityBinding: Binding<Bool> {
        Binding(
            get: { showChords },
            set: { newValue in
                guard newValue != showChords else { return }
                let currentLines = lines(showingChords: showChords)
                let anchorID = currentLines.indices.contains(position) ? currentLines[position].id : nil
                let sourceAnchor = anchorID.flatMap { id in allLines.firstIndex(where: { $0.id == id }) } ?? 0

                showChords = newValue
                let updatedLines = lines(showingChords: newValue)
                if let anchorID,
                   let exactIndex = updatedLines.firstIndex(where: { $0.id == anchorID }) {
                    position = exactIndex
                    return
                }

                let nearest = updatedLines.enumerated().min { lhs, rhs in
                    let lhsSource = allLines.firstIndex(where: { $0.id == lhs.element.id }) ?? 0
                    let rhsSource = allLines.firstIndex(where: { $0.id == rhs.element.id }) ?? 0
                    return Swift.abs(lhsSource - sourceAnchor) < Swift.abs(rhsSource - sourceAnchor)
                }
                position = nearest?.offset ?? 0
            }
        )
    }

    private var applyHelp: String {
        if !isConnected { return "Conecte o PA700 para aplicar esta configuração" }
        if !preset.isReadyToPlay { return "Finalize a configuração em Preparar show" }
        if editingAnnotations { return "Conclua a edição das anotações antes de aplicar" }
        return "Enviar esta configuração ao PA700"
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
                visibleLines.indices.contains(position) ? visibleLines[position].id : visibleLines.first?.id
            },
            set: { lineID in
                guard let lineID, let index = visibleLines.firstIndex(where: { $0.id == lineID }) else { return }
                position = index
            }
        )
    }
}

private struct ShowAnnotationNote: View {
    @Binding var annotation: ShowChartAnnotation
    let canvasSize: CGSize
    let isEditing: Bool
    let onDelete: () -> Void
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        Group {
            if isEditing {
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
                        .accessibilityLabel("Apagar anotação")
                    }
                    .foregroundStyle(LabTheme.annotationInk.opacity(0.62))
                    .padding(.horizontal, 8)
                    .frame(height: 27)
                    .contentShape(Rectangle())
                    .gesture(dragGesture)

                    TextEditor(text: $annotation.text)
                        .font(.system(size: 17, weight: .semibold))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(LabTheme.annotationInk)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 5)
                }
            } else {
                Text(annotation.text)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LabTheme.annotationInk)
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .allowsHitTesting(isEditing)
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
        DragGesture()
            .updating($dragOffset) { value, state, _ in state = value.translation }
            .onEnded { value in
                guard canvasSize.width > 0, canvasSize.height > 0 else { return }
                annotation.normalizedX = min(0.92, max(0.08, (notePosition.x + value.translation.width) / canvasSize.width))
                annotation.normalizedY = min(0.92, max(0.08, (notePosition.y + value.translation.height) / canvasSize.height))
            }
    }

    private func moveAnnotation(dx: Double, dy: Double) {
        guard isEditing else { return }
        annotation.normalizedX = min(0.92, max(0.08, annotation.normalizedX + dx))
        annotation.normalizedY = min(0.92, max(0.08, annotation.normalizedY + dy))
    }
}

private struct ShowKeyboardMonitor: NSViewRepresentable {
    let enabled: Bool
    let onPage: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        context.coordinator.update(enabled: enabled, onPage: onPage)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.update(enabled: enabled, onPage: onPage)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private weak var view: NSView?
        private var enabled = false
        private var onPage: ((Int) -> Void)?
        private var monitor: Any?

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      self.enabled,
                      event.keyCode == 49,
                      let window = self.view?.window,
                      event.windowNumber == window.windowNumber else { return event }

                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                guard modifiers.isEmpty || modifiers == .shift else { return event }
                self.onPage?(modifiers.contains(.shift) ? -8 : 8)
                return nil
            }
        }

        func update(enabled: Bool, onPage: @escaping (Int) -> Void) {
            self.enabled = enabled
            self.onPage = onPage
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

private struct ShowConnectionStrip: View {
    @EnvironmentObject private var model: AppModel
    let focusMode: Bool
    let onToggleFocus: () -> Void
    let onFullScreen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.connected ? "circle.fill" : "circle")
                .foregroundStyle(model.connected ? LabTheme.verified : .secondary)
                .accessibilityLabel(model.connected ? "Conectado" : "Desconectado")
            VStack(alignment: .leading, spacing: 1) {
                Text(model.connected ? "PA700 conectado via USB" : "Nenhum teclado conectado")
                    .fontWeight(.semibold)
                Text(model.connected ? model.showStatus : "Reconecte o USB para liberar as músicas confirmadas")
                    .font(.caption)
                    .foregroundStyle(model.connected ? Color.secondary : LabTheme.draft)
                    .lineLimit(1)
            }
            Spacer()
            Text("MODO SHOW")
                .font(.caption.weight(.bold))
                .foregroundStyle(LabTheme.signal)
            Button(focusMode ? "Sair do foco" : "Foco", systemImage: focusMode ? "rectangle.compress.vertical" : "rectangle.expand.vertical", action: onToggleFocus)
                .help(focusMode ? "Mostrar repertório e detalhes" : "Deixar somente a cifra e os controles de palco")
            Button("Tela cheia", systemImage: "arrow.up.left.and.arrow.down.right", action: onFullScreen)
                .help("Usar o monitor inteiro para o show")
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
}
