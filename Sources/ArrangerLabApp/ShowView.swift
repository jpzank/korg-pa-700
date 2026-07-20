import ArrangerLabCore
import SwiftUI

struct ShowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @FocusState private var focusedItemID: UUID?
    @AppStorage("arrangerlab.showReaderFontSize") private var readerFontSize = 23.0
    @AppStorage("arrangerlab.showReaderChords") private var showChords = true
    @State private var chartPositions: [UUID: Int] = [:]

    var body: some View {
        VStack(spacing: 0) {
            ShowConnectionStrip()
            Divider()

            if let setList = model.activeShowSetList {
                showContent(setList)
            } else {
                emptyState
            }
        }
        .tint(LabTheme.signal)
        .preferredColorScheme(.dark)
        .alert("Arranger Lab", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
        .onAppear {
            focusCurrentOrFirstItem()
            loadReaderDefaults()
        }
        .onChange(of: model.activeShowSetListID) { _, _ in focusCurrentOrFirstItem() }
        .onChange(of: model.activeShowSetListItemID) { _, newValue in
            if let newValue { focusedItemID = newValue }
        }
        .onChange(of: model.activeShowPresetID) { _, _ in loadReaderDefaults() }
    }

    private func showContent(_ setList: ShowSetList) -> some View {
        HStack(spacing: 0) {
            setListRail(setList)
                .frame(width: 300)

            Divider()

            chartStage
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            activePresetPanel(setList)
                .frame(width: 310)
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
                Image(systemName: model.activeShowPresetID == nil ? "circle.dashed" : "checkmark.circle.fill")
                    .foregroundStyle(model.activeShowPresetID == nil ? .secondary : LabTheme.verified)
                Text(model.showStatus)
                    .font(.caption)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(minHeight: 52)
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.34))
    }

    private func showRow(index: Int, item: ShowSetListItem) -> some View {
        let preset = model.showPreset(for: item)
        let isActive = model.activeShowSetListItemID == item.id
        let isReady = preset?.isConfirmed == true

        return Button {
            guard let preset else { return }
            model.applyShowPreset(preset, setListItemID: item.id)
        } label: {
            HStack(spacing: 11) {
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
                        Text(songBookLabel(preset?.songBookNumber))
                        Text("·")
                        Text(isReady ? "Pronta" : "Não pronta")
                            .foregroundStyle(isReady ? Color.secondary : Color.orange)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    if let preset {
                        HStack(spacing: 6) {
                            Text("Mão \(preset.originalKey.isEmpty ? "—" : preset.originalKey)")
                            Text("T \(signedSemitones(preset.transposeSemitones))")
                            Text("Soa \(soundingKey(preset) ?? "—")")
                        }
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(isActive ? LabTheme.signal : .secondary)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: isActive ? "checkmark.circle.fill" : (isReady ? "play.fill" : "lock.fill"))
                    .foregroundStyle(isActive ? LabTheme.verified : (isReady && model.connected ? LabTheme.signal : Color.secondary))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(isActive ? LabTheme.signal.opacity(0.17) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider().opacity(0.55) }
        .focused($focusedItemID, equals: item.id)
        .accessibilityLabel("\(index + 1), \(preset?.songTitle ?? "Preset indisponível")")
        .accessibilityValue(isReady ? "Pronta para o show" : "Não pronta")
        .accessibilityHint(isReady ? "Aplica esta música ao PA700 e abre a cifra" : "Teste e confirme este preset em Preparar show")
    }

    private var chartStage: some View {
        Group {
            if let preset = model.activeShowPreset {
                ShowChartReader(
                    preset: preset,
                    showChords: $showChords,
                    fontSize: $readerFontSize,
                    position: Binding(
                        get: { chartPositions[preset.id] ?? 0 },
                        set: { chartPositions[preset.id] = $0 }
                    )
                )
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Selecione uma música pronta")
                        .font(.title2.weight(.semibold))
                    Text("A cifra só muda depois que o SongBook é enviado com sucesso ao PA700.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                    if !model.connected {
                        Label("Reconecte o PA700 para iniciar", systemImage: "cable.connector.slash")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(red: 0.055, green: 0.060, blue: 0.063))
    }

    private func activePresetPanel(_ setList: ShowSetList) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("AGORA")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            if let preset = model.activeShowPreset {
                VStack(alignment: .leading, spacing: 6) {
                    Text(preset.songTitle)
                        .font(.title2.weight(.semibold))
                        .lineLimit(3)
                    HStack(spacing: 7) {
                        Text(songBookLabel(preset.songBookNumber))
                        Text("Transpose \(signedSemitones(preset.transposeSemitones))")
                    }
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(LabTheme.signal)
                    Text("Mãos: \(preset.originalKey.isEmpty ? "—" : preset.originalKey)  ·  Soa: \(soundingKey(preset) ?? "—")")
                        .font(.callout.monospaced().weight(.semibold))
                        .foregroundStyle(.primary)
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
                Text("Nenhuma música aplicada")
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
                        Text(songBookLabel(next.songBookNumber))
                        Text(transposeText(next.transposeSemitones))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(22)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.4))
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
        guard let activeID = model.activeShowSetListItemID,
              let index = setList.items.firstIndex(where: { $0.id == activeID }),
              setList.items.indices.contains(index + 1) else { return nil }
        return model.showPreset(for: setList.items[index + 1])
    }

    private func focusCurrentOrFirstItem() {
        focusedItemID = model.activeShowSetListItemID ?? model.activeShowSetList?.items.first?.id
    }

    private func loadReaderDefaults() {
        guard let preset = model.activeShowPreset else { return }
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
        focusedItemID = setList.items[nextIndex].id
    }

    private func songBookLabel(_ number: Int?) -> String {
        number.map { "SB \($0)" } ?? "SB —"
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
    @Binding var showChords: Bool
    @Binding var fontSize: Double
    @Binding var position: Int

    private var visibleLines: [ShowChartLine] {
        preset.chartLines.filter { showChords || $0.kind != .chords }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preset.songTitle)
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)
                        if let source = preset.source {
                            Text(source.sourceURL == nil
                                ? "Conteúdo extraído de \(source.documentName)"
                                : "Conteúdo importado de \(source.documentName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Toggle("Cifras", isOn: $showChords)
                        .toggleStyle(.button)
                        .help("Mostrar ou ocultar os acordes")
                    Button {
                        fontSize = max(17, fontSize - 2)
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .help("Diminuir letra")
                    .disabled(fontSize <= 17)
                    Button {
                        fontSize = min(37, fontSize + 2)
                    } label: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .help("Aumentar letra")
                    .disabled(fontSize >= 37)
                    Button("Topo", systemImage: "arrow.up.to.line") { position = 0 }
                        .help("Voltar ao início da cifra")
                }

                HStack(spacing: 0) {
                    toneMetric(label: "TOM NAS MÃOS", value: preset.originalKey.isEmpty ? "—" : preset.originalKey, color: .primary)
                    Divider().frame(height: 38)
                    toneMetric(label: "TRANSPOSE PA700", value: signedSemitones(preset.transposeSemitones), color: LabTheme.chartChord)
                    Divider().frame(height: 38)
                    toneMetric(
                        label: "TOM QUE SOA",
                        value: ShowMusicTheory.transposedKey(preset.originalKey, by: preset.transposeSemitones) ?? "—",
                        color: LabTheme.verified
                    )
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))

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
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(visibleLines.enumerated()), id: \.element.id) { _, line in
                            chartLine(line)
                                .id(line.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 34)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollPosition(id: visibleLineIDBinding, anchor: .top)
                .focusable()
                .accessibilityLabel("Cifra de \(preset.songTitle)")
                .onChange(of: showChords) { _, _ in
                    position = min(position, max(0, visibleLines.count - 1))
                }
                .overlay(alignment: .bottomTrailing) {
                    VStack(spacing: 7) {
                        Button { move(by: -8) } label: { Image(systemName: "chevron.up") }
                            .help("Voltar uma tela")
                        Button { move(by: 8) } label: { Image(systemName: "chevron.down") }
                            .help("Avançar uma tela (Espaço)")
                            .keyboardShortcut(.space, modifiers: [])
                    }
                    .buttonStyle(.bordered)
                    .padding(18)
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
                .font(.system(size: 25, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private func signedSemitones(_ value: Int) -> String {
        value == 0 ? "0" : "\(value > 0 ? "+" : "")\(value)"
    }

    private func move(by amount: Int) {
        withAnimation(.easeOut(duration: 0.2)) {
            position = min(max(0, position + amount), max(0, visibleLines.count - 1))
        }
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

private struct ShowConnectionStrip: View {
    @EnvironmentObject private var model: AppModel

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
                    .foregroundStyle(model.connected ? Color.secondary : Color.orange)
                    .lineLimit(1)
            }
            Spacer()
            Text("MODO SHOW")
                .font(.caption.weight(.bold))
                .foregroundStyle(LabTheme.signal)
            Button("Panic", systemImage: "exclamationmark.octagon.fill") { model.panic() }
                .buttonStyle(.borderedProminent)
                .tint(LabTheme.danger)
                .keyboardShortcut(".", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
