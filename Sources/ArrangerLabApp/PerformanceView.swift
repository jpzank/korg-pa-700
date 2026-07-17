import ArrangerLabCore
import SwiftUI

private enum PerformancePart: String, CaseIterable, Identifiable {
    case upper1 = "Upper 1"
    case upper2 = "Upper 2"
    case upper3 = "Upper 3"
    case lower = "Lower"

    var id: String { rawValue }

    var target: KeyboardPartTarget {
        switch self {
        case .upper1: return try! .init(zone: .right, layer: 1)
        case .upper2: return try! .init(zone: .right, layer: 2)
        case .upper3: return try! .init(zone: .right, layer: 3)
        case .lower: return try! .init(zone: .left, layer: 1)
        }
    }
}

private enum SoundLibraryFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case factory = "Factory"
    case legacy = "Legacy"
    case gmxg = "GM/XG"
    case user = "User"
    var id: String { rawValue }
}

struct PerformanceView: View {
    @EnvironmentObject private var model: AppModel
    @State private var part: PerformancePart = .upper1
    @State private var volume = 0.75
    @State private var expression = 1.0
    @State private var pan = 0.0
    @State private var sustain = false
    @State private var searchText = ""
    @State private var libraryFilter: SoundLibraryFilter = .all
    @State private var categoryFilter = "Todas"
    @State private var favoritesOnly = false
    @State private var styleSearchText = ""
    @State private var styleCategoryFilter = "Todas"
    @State private var keyboardSetSearchText = ""
    @State private var keyboardSetCategoryFilter = "Todas"
    @State private var sceneName = ""
    @State private var setListName = ""
    @State private var intentCommand = ""
    @State private var activeShowSetListID: UUID?
    @State private var showItemIndex = 0

    private var enabled: Bool { model.connected }
    private var verifiedPresets: [DevicePreset] { model.profile.presets.filter { $0.status == .verified } }
    private var categories: [String] {
        ["Todas"] + Set(model.batchSoundEntries.compactMap(\.category)).sorted()
    }
    private var filteredSounds: [BatchSoundEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.batchSoundEntries.filter { entry in
            let libraryMatches: Bool
            switch libraryFilter {
            case .all: libraryMatches = true
            case .factory, .legacy, .gmxg: libraryMatches = entry.library == libraryFilter.rawValue
            case .user: libraryMatches = entry.library == "User" || entry.source == .midiCapture && entry.selection.bankMSB == 121 && (64...67).contains(entry.selection.bankLSB)
            }
            let categoryMatches = categoryFilter == "Todas" || entry.category == categoryFilter
            let favoriteMatches = !favoritesOnly || entry.isFavorite
            let textMatches = query.isEmpty
                || entry.effectiveName.localizedCaseInsensitiveContains(query)
                || entry.selection.display.localizedCaseInsensitiveContains(query)
            return libraryMatches && categoryMatches && favoriteMatches && textMatches
        }.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return $0.effectiveName.localizedStandardCompare($1.effectiveName) == .orderedAscending
        }
    }
    private var styleCategories: [String] {
        ["Todas"] + Set(model.arrangerStyles.map(\.category)).sorted()
    }
    private var filteredStyles: [ArrangerStyle] {
        let query = styleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.arrangerStyles.filter { style in
            (styleCategoryFilter == "Todas" || style.category == styleCategoryFilter)
                && (query.isEmpty || style.displayName.localizedCaseInsensitiveContains(query))
        }
    }
    private var keyboardSetCategories: [String] {
        ["Todas"] + Set(model.keyboardSetLibraryEntries.map(\.category)).sorted()
    }
    private var filteredKeyboardSets: [KeyboardSetLibraryEntry] {
        let query = keyboardSetSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.keyboardSetLibraryEntries.filter { entry in
            (keyboardSetCategoryFilter == "Todas" || entry.category == keyboardSetCategoryFilter)
                && (query.isEmpty || entry.displayName.localizedCaseInsensitiveContains(query))
        }
    }

    private var activeShowSetList: PerformanceSetList? {
        guard let activeShowSetListID else { return nil }
        return model.performanceSetLists.first { $0.id == activeShowSetListID }
    }

    var body: some View {
        Group {
            if let setList = activeShowSetList, !setList.items.isEmpty {
                showMode(setList)
            } else {
                performanceEditor
            }
        }
        .onAppear { loadPartSettings(part) }
        .onChange(of: part) { _, selectedPart in loadPartSettings(selectedPart) }
    }

    private var performanceEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Tocar", subtitle: "Controle o teclado sem pensar em MIDI.")

                musicalAssistant

                Divider()

                sceneBuilder

                setListBuilder

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Parte").font(.headline)
                    Picker("Parte", selection: $part) {
                        ForEach(PerformancePart.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Divider()

                auditionBrowser

                Divider()

                keyboardSetBrowser

                Divider()

                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Timbre").font(.headline)
                            Text("Som exato já verificado no PA700").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ForEach(verifiedPresets, id: \.id) { preset in
                            Button(preset.displayName, systemImage: "pianokeys") {
                                model.selectVerifiedPreset(preset.id, target: part.target, partName: part.rawValue)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(!enabled)
                        }
                    }

                    PerformanceSlider(title: "Volume", value: $volume, range: 0...1, valueText: "\(Int((volume * 100).rounded()))%") {
                        model.setPartVolume(part.target, level: volume, partName: part.rawValue)
                    }
                    .disabled(!enabled)

                    PerformanceSlider(title: "Expressão", value: $expression, range: 0...1, valueText: "\(Int((expression * 100).rounded()))%") {
                        model.setPartExpression(part.target, level: expression, partName: part.rawValue)
                    }
                    .disabled(!enabled)

                    PerformanceSlider(title: "Panorama", value: $pan, range: -1...1, valueText: panDescription) {
                        model.setPartPan(part.target, position: pan, partName: part.rawValue)
                    }
                    .disabled(!enabled)

                    Toggle(isOn: $sustain) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sustain").font(.headline)
                            Text(sustain ? "Ligado" : "Desligado").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .disabled(!enabled)
                    .onChange(of: sustain) { _, engaged in
                        model.setPartDamper(part.target, engaged: engaged, partName: part.rawValue)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Ritmos").font(.headline)
                            Text("379 Styles oficiais do PA700 · seleção exata pelo canal Control")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label(
                            model.styleSelectionOperational ? "Verified" : "Aguardando 1 amostra",
                            systemImage: model.styleSelectionOperational ? "checkmark.seal.fill" : "testtube.2"
                        )
                        .font(.caption)
                        .foregroundStyle(model.styleSelectionOperational ? .green : .orange)
                    }

                    HStack(spacing: 10) {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Buscar Style", text: $styleSearchText).textFieldStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))

                        Picker("Categoria", selection: $styleCategoryFilter) {
                            ForEach(styleCategories, id: \.self) { Text($0).tag($0) }
                        }
                        .frame(width: 155)
                    }

                    List(filteredStyles) { style in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.displayName)
                                Text("\(style.category) · \(style.address)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Selecionar", systemImage: "music.quarternote.3") {
                                model.selectPerformanceStyle(style)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!enabled)
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.inset)
                    .frame(height: 230)

                    HStack(spacing: 10) {
                        Button("Start / Stop", systemImage: "playpause.fill") {
                            model.togglePerformanceArranger()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Text("Variação").foregroundStyle(.secondary)
                        ForEach(1...4, id: \.self) { number in
                            Button(String(number)) {
                                model.selectPerformanceVariation(number)
                            }
                            .controlSize(.large)
                            .frame(minWidth: 44)
                        }
                    }
                    .disabled(!enabled)
                    Text("Start / Stop usa o relógio interno do teclado.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var musicalAssistant: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Assistente musical").font(.headline)
                    Text("Use os nomes exatos do catálogo. O app prepara a cena e espera sua confirmação.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("Interpretação local", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                TextField("Jimmy Organ com Brush Ballad na variação 3", text: $intentCommand)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { prepareIntent() }
                    .onChange(of: intentCommand) { _, _ in
                        if model.performanceIntentPreview != nil {
                            model.clearPerformanceIntentPreview(message: "Comando alterado. Prepare uma nova prévia.")
                        }
                    }
                Button("Preparar prévia", systemImage: "list.bullet.clipboard") { prepareIntent() }
                    .buttonStyle(.borderedProminent)
                    .disabled(intentCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text("Exemplo: Concert Grand com Brush Ballad na variação 2")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if let preview = model.performanceIntentPreview {
                Divider()

                HStack {
                    Text("PRÉVIA").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Label("Somente ações Verified", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                VStack(spacing: 0) {
                    ForEach(preview.changes) { change in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(change.label)
                                .font(.callout.weight(.medium))
                                .frame(width: 130, alignment: .leading)
                            Text(change.previousValue)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(change.nextValue)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 7)
                        if change.id != preview.changes.last?.id { Divider() }
                    }
                }

                HStack {
                    Button("Descartar", systemImage: "xmark") {
                        model.clearPerformanceIntentPreview()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Aplicar ao teclado", systemImage: "play.fill") {
                        model.applyPerformanceIntent()
                        loadPartSettings(part)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!enabled)
                }
            }

            Label(model.performanceIntentStatus, systemImage: model.performanceIntentPreview == nil ? "shield" : "eye")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func showMode(_ setList: PerformanceSetList) -> some View {
        let safeIndex = min(max(showItemIndex, 0), setList.items.count - 1)
        let currentScene = model.performanceScene(for: setList.items[safeIndex])
        let nextScene = safeIndex + 1 < setList.items.count
            ? model.performanceScene(for: setList.items[safeIndex + 1])
            : nil

        return VStack(alignment: .leading, spacing: 24) {
            HStack {
                Button("Sair do Modo Show", systemImage: "chevron.left") {
                    activeShowSetListID = nil
                    showItemIndex = 0
                }
                .buttonStyle(.bordered)

                Spacer()

                Label(
                    enabled ? "PA700 conectado" : "PA700 desconectado",
                    systemImage: enabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(enabled ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(setList.name)
                    .font(.title2.weight(.semibold))
                Text("Cena \(safeIndex + 1) de \(setList.items.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(safeIndex + 1), total: Double(setList.items.count))
                    .accessibilityLabel("Progresso da Set List")
                    .accessibilityValue("Cena \(safeIndex + 1) de \(setList.items.count)")
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("AGORA")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let currentScene {
                    Text(currentScene.name)
                        .font(.system(size: 34, weight: .semibold, design: .default))
                        .lineLimit(2)
                    Text(model.performanceSceneSummary(currentScene))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Button {
                        model.applyPerformanceScene(currentScene)
                        loadPartSettings(part)
                    } label: {
                        Label("Aplicar cena", systemImage: "play.fill")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!enabled)
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityHint("Envia esta cena ao teclado")
                } else {
                    Label("Cena indisponível", systemImage: "exclamationmark.triangle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)

            Divider()

            HStack(spacing: 16) {
                Button {
                    showItemIndex = max(0, safeIndex - 1)
                } label: {
                    Label("Anterior", systemImage: "chevron.left")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(safeIndex == 0)
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button {
                    showItemIndex = min(setList.items.count - 1, safeIndex + 1)
                } label: {
                    Label("Próxima", systemImage: "chevron.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(safeIndex == setList.items.count - 1)
                .keyboardShortcut(.rightArrow, modifiers: [])
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(nextScene == nil ? "ÚLTIMA CENA" : "A SEGUIR")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let nextScene {
                    Text(nextScene.name).font(.title3.weight(.medium))
                    Text(model.performanceSceneSummary(nextScene))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Fim de \(setList.name)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var sceneBuilder: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cenas").font(.headline)
                    Text("Salve o Keyboard Set, Style, variação e mix atuais para recuperar tudo com um clique.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.performanceScenes.count) salvas")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                TextField("Nome da cena", text: $sceneName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveScene() }
                Button("Salvar estado atual", systemImage: "plus") { saveScene() }
                    .buttonStyle(.borderedProminent)
                    .disabled(sceneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Label(model.currentPerformanceSummary, systemImage: "slider.horizontal.3")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.performanceScenes.isEmpty {
                Text("Escolha seus sons e ritmo abaixo, ajuste o mix e salve a primeira cena.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.performanceScenes) { scene in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scene.name).fontWeight(.medium)
                                Text(model.performanceSceneSummary(scene))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Aplicar", systemImage: "play.fill") {
                                model.applyPerformanceScene(scene)
                                loadPartSettings(part)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!enabled)
                            if !model.performanceSetLists.isEmpty {
                                Menu {
                                    ForEach(model.performanceSetLists) { setList in
                                        Button(setList.name) {
                                            model.addPerformanceScene(scene, to: setList)
                                        }
                                    }
                                } label: {
                                    Label("Adicionar", systemImage: "text.badge.plus")
                                }
                                .menuStyle(.borderlessButton)
                                .help("Adicionar a uma Set List")
                            }
                            Button(role: .destructive) { model.deletePerformanceScene(scene) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Excluir cena")
                        }
                        .padding(.vertical, 8)
                        if scene.id != model.performanceScenes.last?.id { Divider() }
                    }
                }
            }

            Text(model.performanceStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var setListBuilder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Set Lists").font(.headline)
                    Text("Organize as cenas na ordem da apresentação.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.performanceSetLists.count) listas")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                TextField("Nome da Set List", text: $setListName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { createSetList() }
                Button("Criar", systemImage: "plus") { createSetList() }
                    .buttonStyle(.borderedProminent)
                    .disabled(setListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if model.performanceSetLists.isEmpty {
                Text("Crie uma lista e use Adicionar nas cenas acima.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 12) {
                    ForEach(model.performanceSetLists) { setList in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(setList.name).fontWeight(.semibold)
                                Text("\(setList.items.count) itens")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Modo Show", systemImage: "play.rectangle.fill") {
                                    activeShowSetListID = setList.id
                                    showItemIndex = 0
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(setList.items.isEmpty)
                                Button(role: .destructive) { model.deletePerformanceSetList(setList) } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("Excluir Set List")
                            }

                            if setList.items.isEmpty {
                                Text("Nenhuma cena adicionada.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(setList.items.enumerated()), id: \.element.id) { index, item in
                                    HStack(spacing: 9) {
                                        Text("\(index + 1)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 20, alignment: .trailing)
                                        if let scene = model.performanceScene(for: item) {
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(scene.name)
                                                Text(model.performanceSceneSummary(scene))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Button("Aplicar", systemImage: "play.fill") {
                                                model.applyPerformanceScene(scene)
                                                loadPartSettings(part)
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .disabled(!enabled)
                                        } else {
                                            Text("Cena indisponível").foregroundStyle(.secondary)
                                            Spacer()
                                        }
                                        Button {
                                            model.movePerformanceSetListItem(item, in: setList, offset: -1)
                                        } label: { Image(systemName: "chevron.up") }
                                        .disabled(index == 0)
                                        .help("Mover para cima")
                                        Button {
                                            model.movePerformanceSetListItem(item, in: setList, offset: 1)
                                        } label: { Image(systemName: "chevron.down") }
                                        .disabled(index == setList.items.count - 1)
                                        .help("Mover para baixo")
                                        Button {
                                            model.removePerformanceSetListItem(item, from: setList)
                                        } label: { Image(systemName: "xmark") }
                                        .help("Remover da Set List")
                                    }
                                    .controlSize(.small)
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var keyboardSetBrowser: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Keyboard Sets").font(.headline)
                    Text("298 combinações oficiais · Piano, Organ, Guitar, Strings e mais")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(
                    model.keyboardSetLibrarySelectionOperational ? "Verified" : "Aguardando 1 amostra",
                    systemImage: model.keyboardSetLibrarySelectionOperational ? "checkmark.seal.fill" : "testtube.2"
                )
                .font(.caption)
                .foregroundStyle(model.keyboardSetLibrarySelectionOperational ? .green : .orange)
            }

            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Buscar Keyboard Set", text: $keyboardSetSearchText).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))

                Picker("Categoria", selection: $keyboardSetCategoryFilter) {
                    ForEach(keyboardSetCategories, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 155)
            }

            List(filteredKeyboardSets) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayName)
                        Text("\(entry.category) · \(entry.address)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Selecionar", systemImage: "rectangle.stack.fill") {
                        model.selectPerformanceKeyboardSet(entry)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!enabled)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
            .frame(height: 230)
        }
    }

    private var auditionBrowser: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Explorar timbres").font(.headline)
                    Text("Ouça qualquer timbre do catálogo e confirme apenas os que quiser verificar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(filteredSounds.count) de \(model.batchSoundEntries.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Buscar nome ou endereço MIDI", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))

                Picker("Biblioteca", selection: $libraryFilter) {
                    ForEach(SoundLibraryFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 120)

                Picker("Categoria", selection: $categoryFilter) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 150)

                Toggle("Favoritos", isOn: $favoritesOnly)
                    .toggleStyle(.button)
                    .help("Mostrar somente favoritos")
            }

            if let pendingID = model.pendingAuditionSoundID,
               let pending = model.batchSoundEntries.first(where: { $0.id == pendingID }) {
                HStack(spacing: 12) {
                    Image(systemName: "ear.badge.checkmark")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Você ouviu \(pending.effectiveName)").font(.headline)
                        Text("O nome exibido e o som no PA700 correspondem?")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Não corresponde") { model.confirmCatalogAudition(matches: false) }
                    Button("Confirmar nome e som", systemImage: "checkmark.seal") {
                        model.confirmCatalogAudition(matches: true)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(12)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            } else {
                HStack(spacing: 8) {
                    if model.auditioningSoundID != nil { ProgressView().controlSize(.small) }
                    Image(systemName: model.auditioningSoundID == nil ? "speaker.wave.2" : "waveform")
                        .foregroundStyle(.secondary)
                    Text(model.auditionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.auditioningSoundID != nil {
                        Button("Cancelar") { model.cancelCatalogAudition() }
                            .controlSize(.small)
                    }
                }
                .frame(minHeight: 28)
            }

            List(filteredSounds) { entry in
                HStack(spacing: 10) {
                    Button {
                        model.toggleCatalogFavorite(id: entry.id)
                    } label: {
                        Image(systemName: entry.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(entry.isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(entry.isFavorite ? "Remover dos favoritos" : "Adicionar aos favoritos")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.effectiveName).lineLimit(1)
                        HStack(spacing: 7) {
                            Text([entry.library, entry.category].compactMap { $0 }.joined(separator: " · "))
                            Text(entry.selection.display)
                                .font(.caption.monospaced())
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    let sampled = entry.verificationBasis == .catalogSampling
                    Label(
                        entry.status == .verified ? (sampled ? "Amostral" : "Verified") : "Draft",
                        systemImage: entry.status == .verified ? (sampled ? "checkmark.circle.fill" : "checkmark.seal.fill") : "pencil.circle"
                    )
                        .font(.caption)
                        .foregroundStyle(entry.status == .verified ? .green : .secondary)
                    Button(entry.id == model.auditioningSoundID ? "Ouvindo…" : "Ouvir", systemImage: "play.fill") {
                        model.auditionCatalogSound(id: entry.id, target: part.target, partName: part.rawValue)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!enabled || model.auditioningSoundID != nil || model.pendingAuditionSoundID != nil)
                }
                .padding(.vertical, 3)
            }
            .listStyle(.inset)
            .frame(height: 360)

            Text("Verified = audição individual. Amostral = catálogo oficial + varredura MIDI/áudio dos bancos + amostras físicas confirmadas. A publicação no perfil operacional continua separada.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var panDescription: String {
        if pan < -0.05 { return "\(Int(abs(pan * 100).rounded()))% E" }
        if pan > 0.05 { return "\(Int((pan * 100).rounded()))% D" }
        return "Centro"
    }

    private func saveScene() {
        if model.saveCurrentPerformanceScene(named: sceneName) { sceneName = "" }
    }

    private func prepareIntent() {
        model.preparePerformanceIntent(intentCommand)
    }

    private func createSetList() {
        if model.createPerformanceSetList(named: setListName) { setListName = "" }
    }

    private func loadPartSettings(_ selectedPart: PerformancePart) {
        let setting = model.performancePartSetting(for: selectedPart.target)
        volume = setting.volume
        expression = setting.expression
        pan = setting.pan
    }
}

private struct PerformanceSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueText: String
    let send: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(valueText).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, onEditingChanged: { editing in
                if !editing { send() }
            })
            .controlSize(.large)
        }
    }
}
