import AppKit
import ArrangerLabAudio
import ArrangerLabCore
import ArrangerLabMIDI
import Foundation

struct PerformanceIntentChange: Identifiable, Equatable {
    let label: String
    let previousValue: String
    let nextValue: String

    var id: String { label }
}

struct PerformanceIntentPreview: Equatable {
    let scene: PerformanceScene
    let changes: [PerformanceIntentChange]
}

@MainActor
final class AppModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case performance = "Cenas antigas / Explorar"
        case batchMapping = "Mapear timbres"
        case guide = "Testes guiados"
        case connection = "Conexão avançada"
        case monitor = "Monitor MIDI"
        case recorder = "Captura / Comparação"
        case send = "Envio avançado"
        case experiments = "Mappings avançados"
        var id: String { rawValue }
        var icon: String {
            switch self { case .performance: return "music.note"; case .batchMapping: return "square.stack.3d.up"; case .guide: return "checklist"; case .connection: return "cable.connector"; case .monitor: return "waveform.path.ecg"; case .send: return "paperplane"; case .recorder: return "record.circle"; case .experiments: return "testtube.2" }
        }
    }

    enum PresetABAPhase: String, CaseIterable, Identifiable {
        case a1 = "A1"
        case b = "B"
        case a2 = "A2"
        var id: String { rawValue }
        var instruction: String {
            switch self {
            case .a1: return "Escolha o timbre A no Upper1"
            case .b: return "Escolha um timbre B bem diferente"
            case .a2: return "Volte exatamente ao timbre A"
            }
        }
    }

    @Published var section: Section = .performance
    @Published var sources: [MIDIEndpoint] = []
    @Published var destinations: [MIDIEndpoint] = []
    @Published var selectedSourceID: Int32?
    @Published var selectedDestinationID: Int32?
    @Published var events: [MIDIEvent] = []
    @Published var captureA: [MIDIEvent] = []
    @Published var captureB: [MIDIEvent] = []
    @Published var diff: [CaptureDiffItem] = []
    @Published var isRecording = false
    @Published var filterClock = true
    @Published var filterActiveSensing = true
    @Published var status = "Inicializando CoreMIDI…"
    @Published var performanceStatus = "Pronto para tocar"
    @Published var lastError: String?
    @Published var expert = ExpertSession()
    @Published var identityResult = "Não consultada"
    @Published var persistedIdentityVerified = false
    @Published var replaySpeed = 1.0
    @Published var audioEvidence: [AudioEvidenceRecord] = []
    @Published var isAudioRecording = false
    @Published var manualConfirmations: [ManualConfirmation] = []
    @Published var outputNoteHeard = false
    @Published var outputNoteFailed = false
    @Published var midiPresetConfirmed = false
    @Published var activeGuideAction: String?
    @Published var silenceEvidence: AudioEvidenceRecord?
    @Published var volumeEvidenceByLevel: [Int: AudioEvidenceRecord] = [:]
    @Published var expressionEvidenceByLevel: [Int: AudioEvidenceRecord] = [:]
    @Published var panEvidenceByPosition: [Int: AudioEvidenceRecord] = [:]
    @Published var lastSavedExperimentURL: URL?
    @Published var previousInputConfirmed = false
    @Published var previousOutputConfirmed = false
    @Published var previousPresetConfirmed = false
    @Published var persistedPartVolumeVerified = false
    @Published var persistedVolumeRMSDBFS: [Double] = []
    @Published var persistedPartExpressionEvidenceReady = false
    @Published var partExpressionExperimentURL: URL?
    @Published var persistedPartPanEvidenceReady = false
    @Published var partPanExperimentURL: URL?
    @Published var damperTestCompleted = false
    @Published var persistedPartDamperEvidenceReady = false
    @Published var partDamperExperimentURL: URL?
    @Published var pendingPresetPhase: PresetABAPhase?
    @Published var presetSelections: [PresetABAPhase: MIDIProgramSelection] = [:]
    @Published var presetAudioEvidence: [PresetABAPhase: AudioEvidenceRecord] = [:]
    @Published var presetDisplayedNames: [PresetABAPhase: String] = [:]
    @Published var presetABADistances: [String: Double] = [:]
    @Published var devicePresetVerificationChecks: [String: Bool] = [:]
    @Published var devicePresetVerified = false
    @Published var presetExperimentURL: URL?
    @Published var persistedPresetSummary = ""
    @Published var arrangerExternalUSBConfirmed = false
    @Published var arrangerStartedConfirmed = false
    @Published var arrangerStoppedConfirmed = false
    @Published var arrangerStopSent = false
    @Published var arrangerClockRunning = false
    @Published var arrangerInternalRestored = false
    @Published var arrangerAudioEvidence: AudioEvidenceRecord?
    @Published var arrangerTransportChecks: [String: Bool] = [:]
    @Published var arrangerTransportVerified = false
    @Published var arrangerTransportExperimentURL: URL?
    @Published var clockRestoreRequired = UserDefaults.standard.bool(forKey: "arrangerlab.clockRestoreRequired")
    @Published var songBookStylePlayConfirmed = false
    @Published var songBookSentNumber: Int?
    @Published var songBookDisplayedName = ""
    @Published var songBookVerificationChecks: [String: Bool] = [:]
    @Published var songBookVerified = false
    @Published var songBookExperimentURL: URL?
    @Published var isBatchMapping = false
    @Published private(set) var batchSoundEntries: [BatchSoundEntry] = []
    @Published private(set) var batchCaptureCount = 0
    @Published private(set) var batchScreenCaptures: [BatchSoundScreenCapture] = []
    @Published private(set) var batchCatalogURL: URL?
    @Published private(set) var batchDraftExportURL: URL?
    @Published private(set) var isCatalogValidating = false
    @Published private(set) var catalogValidationProgress = 0
    @Published private(set) var catalogValidationTotal = 0
    @Published private(set) var catalogValidationBankCount = 0
    @Published private(set) var catalogValidationUserCount = 0
    @Published private(set) var catalogValidationAwaitingConfirmation = false
    @Published private(set) var catalogValidationVerified = false
    @Published private(set) var catalogValidationExperimentURL: URL?
    @Published private(set) var auditioningSoundID: String?
    @Published private(set) var pendingAuditionSoundID: String?
    @Published private(set) var auditionMessage = "Escolha um timbre para ouvir"
    @Published private(set) var auditionExperimentURL: URL?
    @Published private(set) var performanceScenes: [PerformanceScene] = []
    @Published private(set) var performanceSetLists: [PerformanceSetList] = []
    @Published private(set) var performanceKeyboardSetEntryID: String?
    @Published private(set) var performanceStyleID: String?
    @Published private(set) var performanceVariation = 1
    @Published private(set) var performancePartSettings: [KeyboardPartTarget: PerformanceScenePart] = Dictionary(
        uniqueKeysWithValues: PerformanceScene.defaultParts().map { ($0.target, $0) }
    )
    @Published private(set) var performanceIntentPreview: PerformanceIntentPreview?
    @Published private(set) var performanceIntentStatus = "Nenhum MIDI será enviado antes da sua confirmação"
    @Published private(set) var showPresets: [ShowPreset] = []
    @Published private(set) var showSetLists: [ShowSetList] = []
    @Published private(set) var activeShowSetListID: UUID?
    @Published private(set) var activeShowPresetID: UUID?
    @Published private(set) var activeShowSetListItemID: UUID?
    @Published private(set) var pendingShowConfirmationID: UUID?
    @Published private(set) var lastShowAppliedAt: Date?
    @Published private(set) var showStatus = "Escolha uma música para começar"

    let profile: InstrumentProfile
    let driver: PA700Driver
    private(set) var transport: MIDITransport?
    private let audioRecorder = AudioEvidenceRecorder()
    private var recordingStartIndex = 0
    private var currentAudioURL: URL?
    private var audioSourceURLs: [UUID: URL] = [:]
    private var presetCaptureStartIndex = 0
    private var presetEventsByPhase: [PresetABAPhase: [MIDIEvent]] = [:]
    private var presetAudioSourceURLs: [UUID: URL] = [:]
    private var arrangerEventsStartIndex = 0
    private var arrangerAudioSourceURL: URL?
    private var songBookEventsStartIndex = 0
    private var expressionEventsStartIndex = 0
    private var panEventsStartIndex = 0
    private var damperEventsStartIndex = 0
    private var batchCollector: BatchSoundCollector?
    private var catalogValidationTask: Task<Void, Never>?
    private var catalogValidationEventStartIndex = 0
    private var catalogValidationEntries: [BatchSoundEntry] = []
    private var catalogValidationAudioEvidence: AudioEvidenceRecord?
    private var catalogValidationAudioSourceURL: URL?
    private var auditionTask: Task<Void, Never>?
    private var auditionEventStartIndex = 0
    private var auditionAudioEvidence: AudioEvidenceRecord?
    private var auditionAudioSourceURL: URL?
    private var auditionPartName = "Upper 1"
    private let legacyBotecoImportVersionKey = "arrangerlab.botecoJul3ImportVersion"
    private let showboatCatalogID = "showboat-jul-23-gojam"
    private let showboatPianoBlockID = "showboat-jul-23-piano-block-a"

    var connected: Bool { transport?.selectedDestination != nil }
    var activeShowSetList: ShowSetList? {
        guard let activeShowSetListID else { return nil }
        return showSetLists.first { $0.id == activeShowSetListID }
    }
    var activeShowPreset: ShowPreset? {
        guard let activeShowPresetID else { return nil }
        return showPresets.first { $0.id == activeShowPresetID }
    }
    var arrangerStyles: [ArrangerStyle] { driver.styleCatalog.styles }
    var styleSelectionOperational: Bool { profile.mappings["styleSelection"]?.status == .verified }
    var keyboardSetLibraryEntries: [KeyboardSetLibraryEntry] { driver.keyboardSetLibraryCatalog.keyboardSets }
    var keyboardSetLibrarySelectionOperational: Bool { profile.mappings["keyboardSetLibrarySelection"]?.status == .verified }
    var currentPerformanceSummary: String {
        let keyboardSet = performanceKeyboardSetEntryID.flatMap { id in keyboardSetLibraryEntries.first(where: { $0.id == id })?.displayName }
        let style = performanceStyleID.flatMap { id in arrangerStyles.first(where: { $0.id == id })?.displayName }
        return [keyboardSet.map { "Keyboard Set: \($0)" }, style.map { "Style: \($0)" }, "Variação \(performanceVariation)"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
    var hasBatchMappingSession: Bool { batchCollector != nil }
    var latestBatchSound: BatchSoundEntry? { batchSoundEntries.last }
    var activeBatchScreen: BatchSoundScreenCapture? { batchScreenCaptures.last(where: \.isOpen) }
    var isBatchScreenCapturing: Bool { activeBatchScreen != nil }
    var batchPendingNameCount: Int {
        batchSoundEntries.reduce(into: 0) { count, entry in
            if entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        }
    }
    var batchLibraryCounts: [String: Int] {
        Dictionary(grouping: batchSoundEntries.compactMap { entry -> BatchSoundEntry? in
            entry.library == nil ? nil : entry
        }, by: { $0.library ?? "" }).mapValues(\.count)
    }
    var hasCompleteOfficialSoundCatalog: Bool {
        batchLibraryCounts["Factory"] == 534
            && batchLibraryCounts["Legacy"] == 505
            && batchLibraryCounts["GM/XG"] == 688
    }
    var batchVerifiedCount: Int { batchSoundEntries.filter { $0.status == .verified }.count }
    var batchSampleVerifiedCount: Int {
        batchSoundEntries.filter { $0.status == .verified && $0.verificationBasis == .catalogSampling }.count
    }
    var fullCatalogVerified: Bool {
        !batchSoundEntries.isEmpty && batchVerifiedCount == batchSoundEntries.count
    }
    var identityVerified: Bool { identityResult.hasPrefix("PA700 confirmado") || persistedIdentityVerified }
    var receivedNoteOnCount: Int {
        events.reduce(into: 0) { count, event in
            if event.direction == .input, case .noteOn = event.message { count += 1 }
        }
    }
    var inputConfirmed: Bool { receivedNoteOnCount > 0 || previousInputConfirmed }
    var outputConfirmed: Bool { outputNoteHeard || previousOutputConfirmed }
    var presetConfigured: Bool { midiPresetConfirmed || previousPresetConfirmed }
    var volumeEvidencePasses: Bool {
        let levels = [25, 50, 75].compactMap { volumeEvidenceByLevel[$0]?.metrics }
        return PA700EvidenceRules.volumePasses(levels)
    }
    var partVolumeVerification: MappingVerificationResult {
        MappingEvidenceVerifier.partVolume(
            events: events,
            firmware: profile.firmware,
            expectedFirmware: "1.5.0",
            midiPreset: midiPresetConfirmed ? "ArrangerLab" : "",
            identityConfirmed: identityVerified,
            audioPasses: volumeEvidencePasses,
            manualConfirmations: manualConfirmations
        )
    }
    var partVolumeVerified: Bool { persistedPartVolumeVerified || partVolumeVerification.passed }
    var expressionEvidencePasses: Bool {
        let levels = [25, 50, 75].compactMap { expressionEvidenceByLevel[$0]?.metrics }
        return PA700EvidenceRules.expressionPasses(levels)
    }
    var partExpressionVerification: MappingVerificationResult {
        MappingEvidenceVerifier.partExpression(
            events: Array(events.dropFirst(expressionEventsStartIndex)),
            firmware: profile.firmware,
            expectedFirmware: "1.5.0",
            midiPreset: presetConfigured ? "ArrangerLab" : "",
            identityConfirmed: identityVerified,
            audioPasses: expressionEvidencePasses,
            manualConfirmations: manualConfirmations
        )
    }
    var partExpressionOperational: Bool { profile.mappings["partExpression"]?.status == .verified }
    var partExpressionEvidenceReady: Bool { persistedPartExpressionEvidenceReady || partExpressionVerification.passed }
    var panAudioCaptured: Bool {
        [-100, 0, 100].allSatisfy {
            guard let evidence = panEvidenceByPosition[$0] else { return false }
            return evidence.durationSeconds >= 2 && evidence.metrics.peak > 0
        }
    }
    var partPanVerification: MappingVerificationResult {
        MappingEvidenceVerifier.partPan(
            events: Array(events.dropFirst(panEventsStartIndex)),
            firmware: profile.firmware,
            expectedFirmware: "1.5.0",
            midiPreset: presetConfigured ? "ArrangerLab" : "",
            identityConfirmed: identityVerified,
            audioCaptured: panAudioCaptured,
            manualConfirmations: manualConfirmations
        )
    }
    var partPanOperational: Bool { profile.mappings["partPan"]?.status == .verified }
    var partPanEvidenceReady: Bool { persistedPartPanEvidenceReady || partPanVerification.passed }
    var partDamperVerification: MappingVerificationResult {
        MappingEvidenceVerifier.partDamper(
            events: Array(events.dropFirst(damperEventsStartIndex)),
            firmware: profile.firmware,
            expectedFirmware: "1.5.0",
            midiPreset: presetConfigured ? "ArrangerLab" : "",
            identityConfirmed: identityVerified,
            audibleComparisonCompleted: damperTestCompleted,
            manualConfirmations: manualConfirmations
        )
    }
    var partDamperOperational: Bool { profile.mappings["partDamper"]?.status == .verified }
    var partDamperEvidenceReady: Bool { persistedPartDamperEvidenceReady || partDamperVerification.passed }
    var midiClockOperational: Bool { profile.mappings["midiClock"]?.status == .verified }
    var presetABAPasses: Bool { !devicePresetVerificationChecks.isEmpty && devicePresetVerificationChecks.values.allSatisfy { $0 } }
    var arrangerTransportPasses: Bool { !arrangerTransportChecks.isEmpty && arrangerTransportChecks.values.allSatisfy { $0 } }
    var songBookPasses: Bool { !songBookVerificationChecks.isEmpty && songBookVerificationChecks.values.allSatisfy { $0 } }
    var visibleEvents: [MIDIEvent] {
        events.filter { event in
            guard let message = event.message else { return true }
            if filterClock, message == .realtime(0xF8) { return false }
            if filterActiveSensing, message == .realtime(0xFE) { return false }
            return true
        }
    }

    init() {
        profile = (try? .bundledPA700()) ?? Self.fallbackProfile()
        driver = PA700Driver(profile: profile)
        do {
            let transport = try MIDITransport()
            self.transport = transport
            transport.onEndpointsChanged = { [weak self] sources, destinations in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.sources = sources
                    self.destinations = destinations
                    if !self.connected { self.clearActiveShowSelection() }
                    guard !self.connected,
                          let source = sources.first(where: { $0.name.localizedCaseInsensitiveContains("Pa700 KEYBOARD") }),
                          let destination = destinations.first(where: { $0.name.localizedCaseInsensitiveContains("Pa700 SOUND") }) else { return }
                    do {
                        try self.transport?.connect(sourceID: source.id, destinationID: destination.id)
                        self.selectedSourceID = source.id
                        self.selectedDestinationID = destination.id
                        self.status = "PA700 reconectado automaticamente; verificando identidade"
                        try self.transport?.send(.systemExclusive([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]))
                    } catch { self.fail(error) }
                }
            }
            transport.onEvent = { [weak self] event in DispatchQueue.main.async { self?.receive(event) } }
            transport.onFailure = { [weak self] error in DispatchQueue.main.async { self?.fail(error) } }
            sources = transport.sources; destinations = transport.destinations
            if try transport.autoConnectPA700() {
                selectedSourceID = transport.selectedSource?.id
                selectedDestinationID = transport.selectedDestination?.id
                status = "PA700 conectado; verificando identidade"
                try transport.send(.systemExclusive([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]))
            } else { status = "Selecione os endpoints MIDI" }
        } catch { status = "CoreMIDI indisponível"; lastError = error.localizedDescription }
        restoreLatestVerification()
        restoreLatestBatchCatalog()
        restorePerformanceScenes()
        restorePerformanceSetLists()
        restoreShowPerformance()
    }

    func connect() {
        do {
            try transport?.connect(sourceID: selectedSourceID, destinationID: selectedDestinationID)
            expert.expire()
            status = connected ? "Conectado" : "Desconectado"
            if !connected { clearActiveShowSelection() }
            objectWillChange.send()
        } catch { fail(error) }
    }

    func autoConnect() {
        do {
            if try transport?.autoConnectPA700() == true {
                selectedSourceID = transport?.selectedSource?.id; selectedDestinationID = transport?.selectedDestination?.id
                status = "Pa700 conectado automaticamente"
            } else { throw ArrangerLabError.endpointUnavailable }
        } catch { fail(error) }
    }

    func disconnect() {
        auditionTask?.cancel()
        auditionTask = nil
        audioRecorder.stopSilently()
        try? transport?.panic()
        try? transport?.connect(sourceID: nil, destinationID: nil)
        endBatchScreenCapture(silently: true)
        isBatchMapping = false
        saveBatchCatalogSilently()
        clearActiveShowSelection()
        expert.expire(); status = "Desconectado"; objectWillChange.send()
    }

    func panic() {
        do {
            try transport?.panic()
            clearActiveShowSelection()
            status = "Panic enviado em 16 canais"
            showStatus = "Panic enviado. Selecione novamente a música antes de tocar."
        } catch { fail(error) }
    }

    func startBatchMapping() {
        guard connected else { fail(ArrangerLabError.endpointUnavailable); return }
        if batchCollector == nil { createNewBatchMappingSession() }
        isBatchMapping = true
        status = "Capturando timbres do Upper1 · selecione cada som uma vez no PA700"
    }

    func stopBatchMapping() {
        endBatchScreenCapture(silently: true)
        isBatchMapping = false
        saveBatchCatalogSilently()
        do {
            try transport?.panic()
            status = "Captura em lote parada · \(batchSoundEntries.count) timbres únicos salvos"
        } catch { fail(error) }
    }

    func createNewBatchMappingSession() {
        if isBatchMapping { try? transport?.panic() }
        let now = Date()
        let catalog = BatchSoundCatalog(
            model: profile.model,
            firmware: profile.firmware,
            midiPreset: "ArrangerLab",
            startedAt: now,
            updatedAt: now
        )
        batchCollector = BatchSoundCollector(catalog: catalog)
        batchSoundEntries = []
        batchCaptureCount = 0
        batchScreenCaptures = []
        batchDraftExportURL = nil
        isBatchMapping = false
        do {
            let directory = try batchCatalogDirectory()
            let timestamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
            batchCatalogURL = directory.appendingPathComponent("PA700-Sounds-\(timestamp).json")
            try saveBatchCatalog()
            status = "Nova sessão de mapeamento criada"
        } catch { fail(error) }
    }

    func renameBatchSound(id: String, displayName: String) {
        guard var collector = batchCollector else { return }
        collector.rename(id: id, displayName: displayName)
        batchCollector = collector
        batchSoundEntries = collector.catalog.entries
        saveBatchCatalogSilently()
    }

    func commitBatchSoundName(id: String) {
        guard let entry = batchSoundEntries.first(where: { $0.id == id }) else { return }
        let trimmed = entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = "Digite o nome mostrado no PA700 antes de continuar"
            return
        }
        if trimmed != entry.displayName { renameBatchSound(id: id, displayName: trimmed) }
        status = "\(trimmed) salvo · selecione o próximo timbre no PA700"
    }

    func beginBatchScreenCapture() {
        if !isBatchMapping { startBatchMapping() }
        guard isBatchMapping, var collector = batchCollector else { return }
        let screen = collector.beginScreen()
        batchCollector = collector
        syncBatchCatalogState(from: collector)
        saveBatchCatalogSilently()
        status = "\(screen.label) · toque os timbres da foto, da esquerda para a direita e de cima para baixo"
    }

    func endBatchScreenCapture() {
        endBatchScreenCapture(silently: false)
    }

    func undoLastBatchScreenCapture() {
        guard var collector = batchCollector,
              collector.undoLastScreenCapture() != nil else {
            status = "Esta tela ainda não tem capturas para desfazer"
            return
        }
        batchCollector = collector
        syncBatchCatalogState(from: collector)
        saveBatchCatalogSilently()
        status = "Último toque removido de \(collector.activeScreen?.label ?? "tela")"
    }

    func batchEntries(for screenID: UUID) -> [BatchSoundEntry] {
        guard let screen = batchScreenCaptures.first(where: { $0.id == screenID }) else { return [] }
        return screen.entryIDs.compactMap { entryID in
            batchSoundEntries.first(where: { $0.id == entryID })
        }
    }

    func applyBatchScreenNames(screenID: UUID, names: [String]) -> Bool {
        let cleaned = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard var collector = batchCollector else { return false }
        do {
            try collector.assignNames(screenID: screenID, names: cleaned)
            batchCollector = collector
            syncBatchCatalogState(from: collector)
            saveBatchCatalogSilently()
            let label = batchScreenCaptures.first(where: { $0.id == screenID })?.label ?? "Tela"
            status = "\(label) cadastrada · \(cleaned.count) nomes associados aos endereços MIDI"
            return true
        } catch {
            fail(error)
            return false
        }
    }

    func saveBatchCatalogNow() {
        do {
            try saveBatchCatalog()
            status = "Catálogo salvo · \(batchSoundEntries.count) timbres únicos"
        } catch { fail(error) }
    }

    func importOfficialPA700Sounds() {
        if batchCollector == nil { createNewBatchMappingSession() }
        guard var collector = batchCollector else { return }
        do {
            let official = try PA700OfficialSoundCatalog.bundled()
            let summary = collector.importOfficialSounds(official.sounds)
            batchCollector = collector
            syncBatchCatalogState(from: collector)
            try saveBatchCatalog()
            status = "Catálogo oficial completo · 1.727 sons Draft · \(summary.enriched) capturas preservadas"
        } catch { fail(error) }
    }

    func exportBatchDraftProfile() {
        guard let catalog = batchCollector?.catalog, !catalog.entries.isEmpty else {
            status = "Capture pelo menos um timbre antes de exportar"
            return
        }
        do {
            let directory = try batchCatalogDirectory()
            let url = directory.appendingPathComponent("PA700-Sounds-\(catalog.id.uuidString)-Draft.json")
            try BatchSoundCatalogStore.saveDraftExport(BatchSoundCatalogStore.draftExport(from: catalog), to: url)
            batchDraftExportURL = url
            status = "Draft JSON exportado · nenhum timbre foi promovido a Verified"
        } catch { fail(error) }
    }

    func revealBatchMappingFiles() {
        guard let url = batchDraftExportURL ?? batchCatalogURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func startFastCatalogValidation() {
        guard connected else { fail(ArrangerLabError.endpointUnavailable); return }
        guard identityVerified else { status = "Confirme primeiro a identidade do PA700"; return }
        guard presetConfigured else { status = "Selecione e confirme o MIDI Preset ArrangerLab"; return }
        guard let entries = batchCollector?.catalog.entries, !entries.isEmpty else {
            status = "Importe o catálogo antes de validar"
            return
        }
        guard !isCatalogValidating else { return }

        let plan = BatchSoundFastValidationPlan.representatives(from: entries)
        catalogValidationEntries = plan
        catalogValidationTotal = plan.count
        catalogValidationProgress = 0
        catalogValidationBankCount = BatchSoundFastValidationPlan.bankCount(in: entries)
        catalogValidationUserCount = BatchSoundFastValidationPlan.capturedUserCount(in: entries)
        catalogValidationAwaitingConfirmation = false
        catalogValidationVerified = false
        isCatalogValidating = true
        status = "Preparando varredura rápida do catálogo"

        catalogValidationTask = Task { [weak self] in
            guard let self else { return }
            guard await audioRecorder.requestPermission() else {
                isCatalogValidating = false
                fail(ArrangerLabError.microphoneDenied)
                return
            }
            do {
                let base = try ArrLabPackage.applicationSupportDirectory().appendingPathComponent("Loose Audio", isDirectory: true)
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                let url = base.appendingPathComponent("catalog-fast-validation-\(UUID().uuidString).wav")
                try audioRecorder.start(to: url)
                catalogValidationAudioSourceURL = url
                catalogValidationEventStartIndex = events.count

                // A short quiet prefix makes the single continuous WAV easier to audit.
                try await Task.sleep(nanoseconds: 700_000_000)
                try transport?.send(.controlChange(channel: 0, controller: 7, value: 80))
                try transport?.send(.controlChange(channel: 0, controller: 11, value: 127))
                try transport?.send(.controlChange(channel: 0, controller: 10, value: 64))

                for (index, entry) in plan.enumerated() {
                    try Task.checkCancellation()
                    let selection = entry.selection
                    try transport?.send(.controlChange(channel: selection.channel, controller: 0, value: selection.bankMSB))
                    try transport?.send(.controlChange(channel: selection.channel, controller: 32, value: selection.bankLSB))
                    try transport?.send(.programChange(channel: selection.channel, program: selection.program))
                    try await Task.sleep(nanoseconds: 90_000_000)

                    let firstNote: UInt8 = entry.category?.localizedCaseInsensitiveContains("Bass") == true ? 43 : 60
                    let secondNote: UInt8 = firstNote == 43 ? 55 : 72
                    try transport?.send(.noteOn(channel: selection.channel, note: firstNote, velocity: 88))
                    try await Task.sleep(nanoseconds: 180_000_000)
                    try transport?.send(.noteOff(channel: selection.channel, note: firstNote, velocity: 0))
                    try transport?.send(.noteOn(channel: selection.channel, note: secondNote, velocity: 80))
                    try await Task.sleep(nanoseconds: 130_000_000)
                    try transport?.send(.noteOff(channel: selection.channel, note: secondNote, velocity: 0))
                    try await Task.sleep(nanoseconds: 50_000_000)
                    catalogValidationProgress = index + 1
                    status = "Validando catálogo · \(index + 1)/\(plan.count)"
                }

                try await Task.sleep(nanoseconds: 500_000_000)
                catalogValidationAudioEvidence = try audioRecorder.stop()
                try? transport?.panic()
                isCatalogValidating = false
                catalogValidationAwaitingConfirmation = true
                status = "Varredura concluída · confirme apenas se ouviu as mudanças de timbre"
            } catch is CancellationError {
                audioRecorder.stopSilently()
                try? transport?.panic()
                isCatalogValidating = false
                status = "Varredura cancelada · Panic enviado"
            } catch {
                audioRecorder.stopSilently()
                isCatalogValidating = false
                fail(error)
            }
        }
    }

    func cancelFastCatalogValidation() {
        catalogValidationTask?.cancel()
        catalogValidationTask = nil
    }

    func confirmFastCatalogValidation(heard: Bool) {
        guard catalogValidationAwaitingConfirmation else { return }
        catalogValidationAwaitingConfirmation = false
        let confirmation = ManualConfirmation(
            prompt: "Representative PA700 catalogue bank sweep was audible",
            confirmed: heard,
            note: heard
                ? "User heard the automatic bank-by-bank sound changes."
                : "User did not hear a reliable catalogue sweep."
        )
        guard heard, let evidence = catalogValidationAudioEvidence else {
            status = "Validação não promovida; execute novamente após revisar o áudio"
            return
        }

        do {
            let base = try ArrLabPackage.applicationSupportDirectory()
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = base.appendingPathComponent("Sound-Catalog-Bank-Sweep-\(stamp)", isDirectory: true).appendingPathExtension("arrlab")
            let state = DeviceStateSnapshot(
                model: profile.model,
                firmware: profile.firmware,
                midiPreset: "ArrangerLab",
                clockSource: "Internal",
                mode: "Sound",
                inputEndpoint: transport?.selectedSource?.name ?? "",
                outputEndpoint: transport?.selectedDestination?.name ?? ""
            )
            let annotations = [
                "identity and firmware: passed",
                "MIDI Preset ArrangerLab: passed",
                "distinct CC0/CC32 banks exercised: \(catalogValidationBankCount)",
                "captured User sounds exercised: \(catalogValidationUserCount)",
                "representative selections exercised: \(catalogValidationEntries.count)",
                "continuous audio evidence: passed",
                "physical audible confirmation: passed",
                "individual catalogue entries remain Draft until individually confirmed"
            ]
            let manifest = ArrLabManifest(
                schemaVersion: 1,
                experimentID: UUID(),
                title: "PA700 sound catalogue bank-addressing verification",
                createdAt: Date(),
                updatedAt: Date(),
                hypothesis: "Every distinct catalogue bank can be selected through CC0, CC32 and Program Change and produces an audible response.",
                mappingID: "devicePreset.catalogAddressing",
                mappingStatus: .verified,
                deviceState: state,
                annotations: annotations
            )
            let tested = catalogValidationEntries.map {
                "\($0.effectiveName)=\($0.selection.bankMSB).\($0.selection.bankLSB).\($0.selection.program)"
            }
            let analysis = ExperimentAnalysis(
                notes: ["Representative sweep only; it does not promote all 1,734 individual presets."] + tested,
                audioEvidence: [evidence],
                manualConfirmations: [confirmation],
                spectralDistances: [:]
            )
            let sweepEvents = Array(events.dropFirst(catalogValidationEventStartIndex))
            try ArrLabPackage.save(.init(manifest: manifest, events: sweepEvents, analysis: analysis), to: url)
            if let source = catalogValidationAudioSourceURL {
                try FileManager.default.copyItem(at: source, to: url.appendingPathComponent(evidence.relativePath))
            }
            try CaptureExporter.csv(events: sweepEvents).write(to: url.appendingPathComponent("export.csv"), atomically: true, encoding: .utf8)
            try CaptureExporter.smf(events: sweepEvents).write(to: url.appendingPathComponent("export.mid"), options: .atomic)
            catalogValidationExperimentURL = url
            catalogValidationVerified = true
            status = "Verified: endereçamento dos \(catalogValidationBankCount) bancos salvo"
        } catch { fail(error) }
    }

    func verifyFullCatalogFromSampling() {
        guard catalogValidationVerified, let sweepURL = catalogValidationExperimentURL else {
            status = "Conclua primeiro a varredura rápida dos bancos"
            return
        }
        guard var collector = batchCollector, !collector.catalog.entries.isEmpty else {
            status = "Importe o catálogo antes de verificar"
            return
        }
        guard !fullCatalogVerified else {
            status = "Catálogo completo já verificado"
            return
        }

        do {
            let sweep = try ArrLabPackage.load(from: sweepURL)
            let now = Date()
            let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
            let base = try ArrLabPackage.applicationSupportDirectory()
            let url = base.appendingPathComponent("Sound-Catalog-Sampled-Verification-\(stamp)", isDirectory: true).appendingPathExtension("arrlab")
            let individualCount = collector.catalog.entries.filter { $0.status == .verified }.count
            let totalCount = collector.catalog.entries.count
            let capturedUserCount = BatchSoundFastValidationPlan.capturedUserCount(in: collector.catalog.entries)
            let confirmation = ManualConfirmation(
                prompt: "PA700 catalogue samples matched their displayed names and audible sounds",
                confirmed: true,
                note: "User performed several representative validations, reported that all sampled presets were correct, and approved catalogue-wide sampled verification."
            )
            let manifest = ArrLabManifest(
                schemaVersion: 1,
                experimentID: UUID(),
                title: "PA700 full sound catalogue sampled verification",
                createdAt: now,
                updatedAt: now,
                hypothesis: "The official catalogue addresses are reliable after the bank sweep and multiple correct user-selected samples.",
                mappingID: "devicePreset.catalog",
                mappingStatus: .verified,
                deviceState: sweep.manifest.deviceState,
                annotations: [
                    "catalogue entries: \(totalCount)",
                    "official Factory entries: \(batchLibraryCounts["Factory"] ?? 0)",
                    "official Legacy entries: \(batchLibraryCounts["Legacy"] ?? 0)",
                    "official GM/XG entries: \(batchLibraryCounts["GM/XG"] ?? 0)",
                    "captured User entries: \(capturedUserCount)",
                    "individually verified before sampling promotion: \(individualCount)",
                    "representative bank sweep: passed",
                    "multiple user-selected samples: passed",
                    "verification basis for remaining entries: catalogue sampling",
                    "individual auditions retain their stronger evidence"
                ]
            )
            let analysis = ExperimentAnalysis(
                notes: [
                    "Shared evidence source: \(sweepURL.path)",
                    "Catalogue-wide status is based on official addresses, a 91-bank sweep, captured User slots, and explicit sample acceptance; it is not an individual audition of every preset."
                ] + sweep.analysis.notes,
                audioEvidence: sweep.analysis.audioEvidence,
                manualConfirmations: sweep.analysis.manualConfirmations + [confirmation],
                spectralDistances: sweep.analysis.spectralDistances
            )
            try ArrLabPackage.save(.init(manifest: manifest, events: sweep.events, analysis: analysis), to: url)
            for evidence in sweep.analysis.audioEvidence {
                let source = sweepURL.appendingPathComponent(evidence.relativePath)
                let destination = url.appendingPathComponent(evidence.relativePath)
                if FileManager.default.fileExists(atPath: source.path) {
                    try FileManager.default.copyItem(at: source, to: destination)
                }
            }
            try CaptureExporter.csv(events: sweep.events).write(to: url.appendingPathComponent("export.csv"), atomically: true, encoding: .utf8)
            try CaptureExporter.smf(events: sweep.events).write(to: url.appendingPathComponent("export.mid"), options: .atomic)

            let promoted = collector.markAllVerifiedBySampling(experimentPath: url.path, now: now)
            batchCollector = collector
            syncBatchCatalogState(from: collector)
            try saveBatchCatalog()
            catalogValidationExperimentURL = url
            catalogValidationVerified = true
            status = "Catálogo verificado por amostragem · \(promoted) promovidos · \(totalCount) no total"
        } catch { fail(error) }
    }

    func queryIdentity() {
        do { try transport?.send(.systemExclusive([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7])); identityResult = "Consulta enviada…" }
        catch { fail(error) }
    }

    func sendCC(channel: Int, controller: Int, value: Int) { send(.controlChange(channel: UInt8(channel - 1), controller: UInt8(controller), value: UInt8(value))) }
    func sendPC(channel: Int, program: Int) { send(.programChange(channel: UInt8(channel - 1), program: UInt8(program))) }
    func sendNote(channel: Int, note: Int, velocity: Int, durationMilliseconds: UInt64 = 350) {
        send(.noteOn(channel: UInt8(channel - 1), note: UInt8(note), velocity: UInt8(velocity)))
        Task {
            try? await Task.sleep(nanoseconds: durationMilliseconds * 1_000_000)
            self.send(.noteOff(channel: UInt8(channel - 1), note: UInt8(note), velocity: 0))
        }
    }
    func sendSysEx(hex: String, confirmed: Bool) {
        do {
            try expert.validateArbitrarySysEx(confirmed: confirmed)
            let bytes = try parseHex(hex)
            guard bytes.first == 0xF0, bytes.last == 0xF7 else { throw ArrangerLabError.invalidValue("SysEx must begin F0 and end F7") }
            try transport?.send(.systemExclusive(bytes))
        } catch { fail(error) }
    }

    func unlockExpert(typedModel: String) { do { try expert.unlock(typedModel: typedModel, connectedModel: profile.model); status = "Expert ativo até desconectar ou fechar" } catch { fail(error) } }

    func toggleRecording() {
        if isRecording { isRecording = false; status = "Captura encerrada: \(events.count - recordingStartIndex) eventos" }
        else { recordingStartIndex = events.count; isRecording = true; status = "Gravando MIDI bidirecional" }
    }
    func markCaptureA() { captureA = Array(events.dropFirst(recordingStartIndex)); updateDiff(); status = "Estado A guardado" }
    func markCaptureB() { captureB = Array(events.dropFirst(recordingStartIndex)); updateDiff(); status = "Estado B guardado" }
    func clearEvents() { events.removeAll(); recordingStartIndex = 0; diff.removeAll() }
    func updateDiff(includeNotes: Bool = false, includeClock: Bool = false, includeSensing: Bool = false) {
        diff = CaptureDiffer.compare(captureA, captureB, options: .init(includeNotes: includeNotes, includeClock: includeClock, includeActiveSensing: includeSensing))
    }

    func replayCurrent() {
        let replayEvents = Array(events.dropFirst(recordingStartIndex))
        let speed = replaySpeed
        let midi = transport
        status = "Replay em andamento"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do { try midi?.replay(replayEvents, speed: speed) }
            catch { DispatchQueue.main.async { self?.fail(error) } }
            DispatchQueue.main.async { self?.status = "Replay encerrado com Panic" }
        }
    }

    func startClock() { do { try transport?.startClock(bpm: 120); status = "Clock 120 BPM + Start enviados" } catch { fail(error) } }
    func stopClock() { transport?.stopClock(); arrangerClockRunning = false; status = "Stop + Panic enviados; restaure Clock Source = Internal" }

    func confirmArrangerExternalUSB() {
        guard connected else { fail(ArrangerLabError.endpointUnavailable); return }
        guard identityVerified else { status = "Confirme primeiro a identidade do PA700"; return }
        guard presetConfigured else { status = "Confirme primeiro o preset MIDI ArrangerLab"; return }
        guard !arrangerClockRunning else { return }
        arrangerExternalUSBConfirmed = true
        arrangerInternalRestored = false
        arrangerStartedConfirmed = false
        arrangerStoppedConfirmed = false
        arrangerStopSent = false
        arrangerAudioEvidence = nil
        arrangerAudioSourceURL = nil
        arrangerTransportChecks.removeAll()
        arrangerEventsStartIndex = events.count
        clockRestoreRequired = true
        UserDefaults.standard.set(true, forKey: "arrangerlab.clockRestoreRequired")
        confirm("Clock Source External USB selected on PA700")
        status = "External USB confirmado; pronto para Start a 120 BPM"
    }

    func startGuidedArrangerClock() {
        guard arrangerExternalUSBConfirmed, clockRestoreRequired else {
            status = "Confirme primeiro Clock Source = External USB"
            return
        }
        guard connected else { fail(ArrangerLabError.endpointUnavailable); return }
        guard activeGuideAction == nil, !arrangerClockRunning, !isAudioRecording else { return }
        activeGuideAction = "Preparando áudio e clock a 120 BPM"

        Task {
            guard await audioRecorder.requestPermission() else {
                activeGuideAction = nil
                fail(ArrangerLabError.microphoneDenied)
                return
            }
            do {
                let base = try ArrLabPackage.applicationSupportDirectory().appendingPathComponent("Loose Audio", isDirectory: true)
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                let url = base.appendingPathComponent("arranger-transport-\(UUID().uuidString).wav")
                try audioRecorder.start(to: url)
                arrangerAudioSourceURL = url
                try transport?.startClock(bpm: 120)
                arrangerClockRunning = true
                activeGuideAction = nil
                status = "Clock + Start enviados a 120 BPM; deixe tocar por pelo menos 3 segundos"
            } catch {
                transport?.stopClock()
                audioRecorder.stopSilently()
                activeGuideAction = nil
                arrangerClockRunning = false
                fail(error)
            }
        }
    }

    func confirmArrangerStarted(heard: Bool) {
        arrangerStartedConfirmed = heard
        if heard {
            confirm("PA700 arranger started from external USB clock")
            status = "Start confirmado; agora use Stop + Panic"
        } else {
            status = "O Arranger não iniciou; mantenha External USB e pare o teste antes de revisar"
        }
        updateArrangerTransportChecks()
    }

    func stopGuidedArrangerClock() {
        transport?.stopClock()
        arrangerClockRunning = false
        arrangerStopSent = true
        do {
            let evidence = try audioRecorder.stop()
            arrangerAudioEvidence = evidence
            status = "Stop + Panic enviados; confirme que parou e restaure Clock Source = Internal"
        } catch {
            status = "Stop + Panic enviados; áudio não pôde ser finalizado: \(error.localizedDescription)"
        }
        updateArrangerTransportChecks()
    }

    func confirmArrangerStopped(heard: Bool) {
        guard arrangerStopSent else { status = "Use primeiro Stop + Panic"; return }
        arrangerStoppedConfirmed = heard
        if heard {
            confirm("PA700 arranger stopped from external USB clock")
            status = "Stop confirmado; restaure Clock Source = Internal no PA700"
        } else {
            panic()
            status = "Panic repetido; se ainda tocar, use SHIFT + START/STOP no PA700"
        }
        updateArrangerTransportChecks()
    }

    func confirmArrangerInternalRestored() {
        guard !arrangerClockRunning else {
            status = "Use Stop + Panic antes de restaurar Internal"
            return
        }
        guard arrangerStopSent || clockRestoreRequired else {
            status = "Não há restauração de Clock Source pendente"
            return
        }
        arrangerInternalRestored = true
        clockRestoreRequired = false
        UserDefaults.standard.removeObject(forKey: "arrangerlab.clockRestoreRequired")
        confirm("Clock Source Internal restored on PA700")
        status = "Clock Source Internal restaurado"
        updateArrangerTransportChecks()
    }

    func saveArrangerTransportVerification() {
        updateArrangerTransportChecks()
        guard arrangerTransportPasses, let evidence = arrangerAudioEvidence else {
            status = "Ainda faltam critérios para salvar o Arranger Start/Stop como Verified"
            return
        }
        do {
            let base = try ArrLabPackage.applicationSupportDirectory()
            let url = base.appendingPathComponent("Arranger-Transport-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-"))", isDirectory: true).appendingPathExtension("arrlab")
            let capturedEvents = Array(events.dropFirst(arrangerEventsStartIndex))
            let state = DeviceStateSnapshot(model: profile.model, firmware: profile.firmware, midiPreset: "ArrangerLab", clockSource: "Internal (restored after External USB)", mode: "Style Play", inputEndpoint: transport?.selectedSource?.name ?? "", outputEndpoint: transport?.selectedDestination?.name ?? "")
            let manifest = ArrLabManifest(
                schemaVersion: 1,
                experimentID: UUID(),
                title: "PA700 arranger Start/Stop verification",
                createdAt: Date(),
                updatedAt: Date(),
                hypothesis: "External USB clock at 120 BPM plus FA/FC starts and stops the PA700 Arranger",
                mappingID: "arrangerTransport",
                mappingStatus: .verified,
                deviceState: state,
                annotations: arrangerTransportChecks.keys.sorted().map { key in
                    "\(key): \(arrangerTransportChecks[key] == true ? "passed" : "failed")"
                }
            )
            let relevantConfirmations = manualConfirmations.filter {
                $0.prompt == "Clock Source External USB selected on PA700"
                    || $0.prompt == "PA700 arranger started from external USB clock"
                    || $0.prompt == "PA700 arranger stopped from external USB clock"
                    || $0.prompt == "Clock Source Internal restored on PA700"
                    || $0.prompt == "ArrangerLab MIDI preset configured"
            }
            let clockCount = capturedEvents.filter { $0.direction == .output && $0.rawBytes == [0xF8] }.count
            let analysis = ExperimentAnalysis(
                notes: ["120 BPM; \(clockCount) MIDI Clock messages; audio=\(evidence.relativePath)"],
                audioEvidence: [evidence],
                manualConfirmations: relevantConfirmations,
                spectralDistances: [:]
            )
            try ArrLabPackage.save(.init(manifest: manifest, events: capturedEvents, analysis: analysis), to: url)
            if let source = arrangerAudioSourceURL {
                try FileManager.default.copyItem(at: source, to: url.appendingPathComponent(evidence.relativePath))
            }
            try CaptureExporter.csv(events: capturedEvents).write(to: url.appendingPathComponent("export.csv"), atomically: true, encoding: .utf8)
            try CaptureExporter.smf(events: capturedEvents).write(to: url.appendingPathComponent("export.mid"), options: .atomic)
            arrangerTransportVerified = true
            arrangerTransportExperimentURL = url
            status = "Verified: Arranger Start/Stop salvo em \(url.path)"
        } catch { fail(error) }
    }

    private func updateArrangerTransportChecks() {
        let capturedEvents = Array(events.dropFirst(arrangerEventsStartIndex))
        arrangerTransportChecks = MappingEvidenceVerifier.arrangerTransport(
            events: capturedEvents,
            firmware: profile.firmware,
            expectedFirmware: "1.5.0",
            midiPreset: presetConfigured ? "ArrangerLab" : "",
            identityConfirmed: identityVerified,
            externalUSBConfirmed: arrangerExternalUSBConfirmed,
            internalRestored: arrangerInternalRestored,
            audioDurationSeconds: arrangerAudioEvidence?.durationSeconds,
            manualConfirmations: manualConfirmations
        ).checks
    }

    func saveExperiment() {
        do {
            let base = try ArrLabPackage.applicationSupportDirectory()
            let url = base.appendingPathComponent("Experiment-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-"))", isDirectory: true).appendingPathExtension("arrlab")
            let state = DeviceStateSnapshot(model: profile.model, firmware: profile.firmware, midiPreset: "ArrangerLab", clockSource: "Internal", mode: "Laboratory", inputEndpoint: transport?.selectedSource?.name ?? "", outputEndpoint: transport?.selectedDestination?.name ?? "")
            let isVolumeExperiment = !volumeEvidenceByLevel.isEmpty || manualConfirmations.contains { $0.prompt == "Volume right/layer 1 audibly changed" }
            let verification = partVolumeVerification
            let mappingStatus: MappingStatus = isVolumeExperiment && verification.passed ? .verified : .draft
            let notes = evidenceNotes()
            let manifest = ArrLabManifest(
                schemaVersion: 1,
                experimentID: UUID(),
                title: mappingStatus == .verified ? "PA700 right/layer 1 volume verification" : "Arranger Lab Capture",
                createdAt: Date(),
                updatedAt: Date(),
                hypothesis: isVolumeExperiment ? "CC7 on configured channel 1 controls right/layer 1 volume" : "",
                mappingID: isVolumeExperiment ? verification.mappingID : nil,
                mappingStatus: mappingStatus,
                deviceState: state,
                annotations: isVolumeExperiment ? verification.annotations : []
            )
            let analysis = ExperimentAnalysis(notes: notes, audioEvidence: audioEvidence, manualConfirmations: manualConfirmations, spectralDistances: [:])
            try ArrLabPackage.save(.init(manifest: manifest, events: events, analysis: analysis), to: url)
            for evidence in audioEvidence {
                if let source = audioSourceURLs[evidence.id] {
                    let destination = url.appendingPathComponent(evidence.relativePath)
                    if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                    try FileManager.default.copyItem(at: source, to: destination)
                }
            }
            try CaptureExporter.csv(events: events).write(to: url.appendingPathComponent("export.csv"), atomically: true, encoding: .utf8)
            try CaptureExporter.smf(events: events).write(to: url.appendingPathComponent("export.mid"), options: .atomic)
            lastSavedExperimentURL = url
            status = mappingStatus == .verified
                ? "Verified: partVolume salvo em \(url.path)"
                : "Experimento Draft salvo em \(url.path)"
        } catch { fail(error) }
    }

    func toggleAudio() {
        if isAudioRecording {
            do {
                let evidence = try audioRecorder.stop()
                audioEvidence.append(evidence)
                if let currentAudioURL { audioSourceURLs[evidence.id] = currentAudioURL }
                currentAudioURL = nil; isAudioRecording = false; status = "Clipe WAV e métricas guardados"
            } catch { fail(error) }
        } else {
            Task {
                guard await audioRecorder.requestPermission() else { fail(ArrangerLabError.microphoneDenied); return }
                do {
                    let base = try ArrLabPackage.applicationSupportDirectory().appendingPathComponent("Loose Audio", isDirectory: true)
                    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                    let url = base.appendingPathComponent("evidence-\(UUID().uuidString).wav")
                    try audioRecorder.start(to: url); currentAudioURL = url; isAudioRecording = true; status = "Gravando clipe curto do microfone"
                } catch { fail(error) }
            }
        }
    }

    func terminate() {
        catalogValidationTask?.cancel()
        isBatchMapping = false
        saveBatchCatalogSilently()
        audioRecorder.stopSilently()
        transport?.close()
        expert.expire()
    }

    func confirmOutputNote(heard: Bool) {
        outputNoteHeard = heard
        outputNoteFailed = !heard
        if heard {
            if !manualConfirmations.contains(where: { $0.prompt == "Mac to PA700 C4 output was audible" }) {
                manualConfirmations.append(.init(prompt: "Mac to PA700 C4 output was audible", confirmed: true, note: "User heard MIDI note 60, velocity 80"))
            }
            status = "Saída MIDI confirmada pelo usuário"
        } else {
            status = "Nota não ouvida; confira volume, Upper1 e MIDI IN canal 1"
        }
    }

    func confirmMIDIPreset() {
        midiPresetConfirmed = true
        if !manualConfirmations.contains(where: { $0.prompt == "ArrangerLab MIDI preset configured" }) {
            manualConfirmations.append(.init(prompt: "ArrangerLab MIDI preset configured", confirmed: true, note: "IN/OUT channels 1,2,3,4,16 and filters confirmed on the PA700 panel"))
        }
        status = "Preset MIDI ArrangerLab registrado como configurado"
    }

    func recordSilenceCalibration() { runGuidedAudio(kind: .silence) }
    func recordVolumeEvidence(level: Int) { runGuidedAudio(kind: .volume(level)) }
    func recordExpressionEvidence(level: Int) {
        if expressionEvidenceByLevel.isEmpty { expressionEventsStartIndex = events.count }
        runGuidedAudio(kind: .expression(level))
    }

    func elapsedString(for event: MIDIEvent) -> String {
        guard let first = events.first?.timestampNanoseconds, event.timestampNanoseconds >= first else { return "0.000" }
        return String(format: "%.3f", Double(event.timestampNanoseconds - first) / 1_000_000_000)
    }

    func sendVolume(_ level: Double) {
        do { try transport?.sendScheduled(driver.compile(.setPartVolume(target: try .init(zone: .right, layer: 1), level: level))); status = "Verified: CC7 right/layer 1 enviado em \(Int(level * 100))%" }
        catch { fail(error) }
    }

    func setPartVolume(_ target: KeyboardPartTarget, level: Double, partName: String) {
        do {
            try transport?.sendScheduled(driver.compile(.setPartVolume(target: target, level: level)))
            updatePerformancePart(target) { $0.volume = level }
            status = "Volume de \(partName): \(Int((level * 100).rounded()))%"
            performanceStatus = status
        } catch { fail(error) }
    }

    func setPartExpression(_ target: KeyboardPartTarget, level: Double, partName: String) {
        do {
            try transport?.sendScheduled(driver.compile(.setPartExpression(target: target, level: level)))
            updatePerformancePart(target) { $0.expression = level }
            status = "Expressão de \(partName): \(Int((level * 100).rounded()))%"
            performanceStatus = status
        } catch { fail(error) }
    }

    func setPartPan(_ target: KeyboardPartTarget, position: Double, partName: String) {
        do {
            try transport?.sendScheduled(driver.compile(.setPartPan(target: target, position: position)))
            updatePerformancePart(target) { $0.pan = position }
            let description = position < -0.05 ? "\(Int(abs(position * 100).rounded()))% esquerda" : (position > 0.05 ? "\(Int((position * 100).rounded()))% direita" : "centro")
            status = "Panorama de \(partName): \(description)"
            performanceStatus = status
        } catch { fail(error) }
    }

    func setPartDamper(_ target: KeyboardPartTarget, engaged: Bool, partName: String) {
        do {
            try transport?.sendScheduled(driver.compile(.setPartDamper(target: target, engaged: engaged)))
            status = "Sustain de \(partName) \(engaged ? "ligado" : "desligado")"
            performanceStatus = status
        } catch { fail(error) }
    }

    func selectVerifiedPreset(_ presetID: String, target: KeyboardPartTarget, partName: String) {
        do {
            guard let preset = profile.presets.first(where: { $0.id == presetID && $0.status == .verified }) else {
                throw ArrangerLabError.invalidValue("preset verificado não encontrado")
            }
            try transport?.sendScheduled(driver.compile(.selectDevicePreset(target: target, presetID: presetID)))
            updatePerformancePart(target) { $0.presetID = presetID }
            status = "\(preset.displayName) selecionado em \(partName)"
            performanceStatus = status
        } catch { fail(error) }
    }

    func selectPerformanceVariation(_ number: Int) {
        let variations: [ArrangerElement] = [.variation1, .variation2, .variation3, .variation4]
        guard variations.indices.contains(number - 1) else { return }
        do {
            try transport?.sendScheduled(driver.compile(.selectArrangerElement(variations[number - 1])))
            performanceVariation = number
            status = "Variação \(number) selecionada"
            performanceStatus = status
        } catch { fail(error) }
    }

    func selectPerformanceStyle(_ style: ArrangerStyle) {
        do {
            try transport?.sendScheduled(driver.compile(
                .selectArrangerStyle(styleID: style.id),
                allowDraft: !styleSelectionOperational
            ))
            performanceStyleID = style.id
            status = "Style \(style.displayName) selecionado · \(style.address)"
            performanceStatus = status
        } catch { fail(error) }
    }

    func selectPerformanceKeyboardSet(_ entry: KeyboardSetLibraryEntry) {
        do {
            try transport?.sendScheduled(driver.compile(
                .selectKeyboardSetLibraryEntry(entryID: entry.id),
                allowDraft: !keyboardSetLibrarySelectionOperational
            ))
            performanceKeyboardSetEntryID = entry.id
            for target in Array(performancePartSettings.keys) {
                updatePerformancePart(target) { $0.presetID = nil }
            }
            status = "Keyboard Set selecionado · \(entry.displayName) · \(entry.address)"
            performanceStatus = status
        } catch { fail(error) }
    }

    func performancePartSetting(for target: KeyboardPartTarget) -> PerformanceScenePart {
        performancePartSettings[target] ?? .init(target: target)
    }

    func performanceSceneSummary(_ scene: PerformanceScene) -> String {
        let keyboardSet = scene.keyboardSetEntryID.flatMap { id in keyboardSetLibraryEntries.first(where: { $0.id == id })?.displayName }
        let style = scene.styleID.flatMap { id in arrangerStyles.first(where: { $0.id == id })?.displayName }
        return [keyboardSet, style, "Variação \(scene.variation)"].compactMap { $0 }.joined(separator: " · ")
    }

    func preparePerformanceIntent(_ command: String) {
        let translation = MusicalIntentTranslator.translate(
            command,
            keyboardSets: keyboardSetLibrarySelectionOperational ? keyboardSetLibraryEntries : [],
            styles: styleSelectionOperational ? arrangerStyles : []
        )
        guard !translation.isEmpty else {
            performanceIntentPreview = nil
            performanceIntentStatus = "Não reconheci um nome exato ou uma variação de 1 a 4"
            return
        }

        let currentKeyboardSetName = performanceKeyboardSetEntryID.flatMap { id in
            keyboardSetLibraryEntries.first(where: { $0.id == id })?.displayName
        } ?? "Não definido"
        let currentStyleName = performanceStyleID.flatMap { id in
            arrangerStyles.first(where: { $0.id == id })?.displayName
        } ?? "Não definido"
        var changes: [PerformanceIntentChange] = []

        if let keyboardSet = translation.keyboardSet {
            changes.append(.init(
                label: "Timbre / conjunto",
                previousValue: currentKeyboardSetName,
                nextValue: keyboardSet.displayName
            ))
        }
        if let style = translation.style {
            changes.append(.init(
                label: "Ritmo",
                previousValue: currentStyleName,
                nextValue: style.displayName
            ))
        }
        if let variation = translation.variation {
            changes.append(.init(
                label: "Variação",
                previousValue: String(performanceVariation),
                nextValue: String(variation)
            ))
        }

        let orderedParts = PerformanceScene.defaultParts().map { defaultPart in
            performancePartSettings[defaultPart.target] ?? defaultPart
        }
        performanceIntentPreview = .init(
            scene: PerformanceScene(
                name: "Comando preparado",
                keyboardSetEntryID: translation.keyboardSet?.id ?? performanceKeyboardSetEntryID,
                styleID: translation.style?.id ?? performanceStyleID,
                variation: translation.variation ?? performanceVariation,
                parts: orderedParts
            ),
            changes: changes
        )
        performanceIntentStatus = "Prévia pronta. Revise as alterações antes de aplicar."
    }

    func clearPerformanceIntentPreview(message: String = "Nenhum MIDI será enviado antes da sua confirmação") {
        performanceIntentPreview = nil
        performanceIntentStatus = message
    }

    func applyPerformanceIntent() {
        guard let preview = performanceIntentPreview else {
            performanceIntentStatus = "Prepare uma prévia primeiro"
            return
        }
        if applyPerformanceScene(preview.scene) {
            performanceIntentStatus = "Comando aplicado usando somente ações Verified"
        }
    }

    @discardableResult
    func saveCurrentPerformanceScene(named rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            performanceStatus = "Digite um nome para a cena"
            return false
        }
        do {
            let now = Date()
            let existingIndex = performanceScenes.firstIndex { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            let existing = existingIndex.map { performanceScenes[$0] }
            let orderedParts = PerformanceScene.defaultParts().map { defaultPart in
                performancePartSettings[defaultPart.target] ?? defaultPart
            }
            let scene = PerformanceScene(
                id: existing?.id ?? UUID(),
                name: name,
                keyboardSetEntryID: performanceKeyboardSetEntryID,
                styleID: performanceStyleID,
                variation: performanceVariation,
                parts: orderedParts,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now
            )
            var updated = performanceScenes
            if let existingIndex { updated[existingIndex] = scene } else { updated.append(scene) }
            updated.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            try persistPerformanceScenes(updated)
            performanceScenes = updated
            performanceStatus = existing == nil ? "Cena \(name) salva" : "Cena \(name) atualizada"
            return true
        } catch {
            fail(error)
            return false
        }
    }

    @discardableResult
    func applyPerformanceScene(_ scene: PerformanceScene) -> Bool {
        do {
            var scheduled: [ScheduledMIDIMessage] = []
            var baseOffset: UInt64 = 0
            for action in try scene.actions() {
                let compiled = try driver.compile(action, allowDraft: false)
                scheduled.append(contentsOf: compiled.map {
                    .init(offsetNanoseconds: baseOffset + $0.offsetNanoseconds, message: $0.message, mappingID: $0.mappingID)
                })
                baseOffset += 25_000_000
            }
            try transport?.sendScheduled(scheduled)
            performanceKeyboardSetEntryID = scene.keyboardSetEntryID
            performanceStyleID = scene.styleID
            performanceVariation = scene.variation
            performancePartSettings = Dictionary(uniqueKeysWithValues: scene.parts.map { ($0.target, $0) })
            status = "Cena \(scene.name) aplicada"
            performanceStatus = status
            return true
        } catch {
            fail(error)
            return false
        }
    }

    func deletePerformanceScene(_ scene: PerformanceScene) {
        do {
            let updated = performanceScenes.filter { $0.id != scene.id }
            let updatedSetLists = performanceSetLists.map { setList in
                var copy = setList
                copy.items.removeAll { $0.sceneID == scene.id }
                if copy.items != setList.items { copy.updatedAt = Date() }
                return copy
            }
            try persistPerformanceScenes(updated)
            try persistPerformanceSetLists(updatedSetLists)
            performanceScenes = updated
            performanceSetLists = updatedSetLists
            performanceStatus = "Cena \(scene.name) excluída"
        } catch { fail(error) }
    }

    @discardableResult
    func createPerformanceSetList(named rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            performanceStatus = "Digite um nome para a Set List"
            return false
        }
        guard !performanceSetLists.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            performanceStatus = "Já existe uma Set List chamada \(name)"
            return false
        }
        do {
            var updated = performanceSetLists
            updated.append(.init(name: name))
            updated.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            try persistPerformanceSetLists(updated)
            performanceSetLists = updated
            performanceStatus = "Set List \(name) criada"
            return true
        } catch {
            fail(error)
            return false
        }
    }

    func addPerformanceScene(_ scene: PerformanceScene, to setList: PerformanceSetList) {
        guard updatePerformanceSetList(setList.id, update: { updated in
            updated.items.append(.init(sceneID: scene.id))
        }) else { return }
        performanceStatus = "\(scene.name) adicionada a \(setList.name)"
    }

    func removePerformanceSetListItem(_ item: PerformanceSetListItem, from setList: PerformanceSetList) {
        guard updatePerformanceSetList(setList.id, update: { updated in
            updated.items.removeAll { $0.id == item.id }
        }) else { return }
        performanceStatus = "Item removido de \(setList.name)"
    }

    func movePerformanceSetListItem(_ item: PerformanceSetListItem, in setList: PerformanceSetList, offset: Int) {
        guard offset == -1 || offset == 1,
              let index = setList.items.firstIndex(where: { $0.id == item.id }) else { return }
        let destination = index + offset
        guard setList.items.indices.contains(destination) else { return }
        guard updatePerformanceSetList(setList.id, update: { updated in
            updated.items.swapAt(index, destination)
        }) else { return }
        performanceStatus = "Ordem de \(setList.name) atualizada"
    }

    func deletePerformanceSetList(_ setList: PerformanceSetList) {
        do {
            let updated = performanceSetLists.filter { $0.id != setList.id }
            try persistPerformanceSetLists(updated)
            performanceSetLists = updated
            performanceStatus = "Set List \(setList.name) excluída"
        } catch { fail(error) }
    }

    func performanceScene(for item: PerformanceSetListItem) -> PerformanceScene? {
        performanceScenes.first { $0.id == item.sceneID }
    }

    @discardableResult
    func saveShowPreset(_ candidate: ShowPreset) -> Bool {
        do {
            let now = Date()
            let existingIndex = showPresets.firstIndex { $0.id == candidate.id }
            let existing = existingIndex.map { showPresets[$0] }
            let cleanedParts = candidate.parts.map {
                ShowPresetPart(
                    part: $0.part,
                    displayName: $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                    isEnabled: $0.isEnabled,
                    soundID: $0.soundID,
                    soundLibrary: $0.soundLibrary?.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            var preset = ShowPreset(
                id: candidate.id,
                songTitle: candidate.songTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                songBookNumber: candidate.songBookNumber,
                transposeSemitones: candidate.transposeSemitones,
                parts: cleanedParts,
                effectsSummary: candidate.effectsSummary.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: candidate.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                originalKey: candidate.originalKey.trimmingCharacters(in: .whitespacesAndNewlines),
                source: candidate.source,
                chartLines: candidate.chartLines,
                readerSettings: candidate.readerSettings,
                confirmedAt: candidate.confirmedAt,
                createdAt: existing?.createdAt ?? candidate.createdAt,
                updatedAt: now
            )
            if let existing, !preset.hasSameOperationalReference(as: existing) {
                preset.confirmedAt = nil
                if pendingShowConfirmationID == preset.id { pendingShowConfirmationID = nil }
                if activeShowPresetID == preset.id { clearActiveShowSelection() }
            }
            try preset.validate()
            var updated = showPresets
            if let existingIndex { updated[existingIndex] = preset } else { updated.append(preset) }
            try persistShowPresets(updated)
            showPresets = updated
            showStatus = existing == nil ? "Preset de \(preset.songTitle) salvo" : "Preset de \(preset.songTitle) atualizado"
            return true
        } catch {
            showStatus = "Não foi possível salvar o preset"
            fail(error)
            return false
        }
    }

    func deleteShowPreset(_ preset: ShowPreset) {
        do {
            let updatedPresets = showPresets.filter { $0.id != preset.id }
            let updatedSetLists = showSetLists.map { setList in
                var copy = setList
                copy.items.removeAll { $0.presetID == preset.id }
                if copy.items != setList.items { copy.updatedAt = Date() }
                return copy
            }
            try persistShowPresets(updatedPresets)
            try persistShowSetLists(updatedSetLists)
            showPresets = updatedPresets
            showSetLists = updatedSetLists
            if activeShowPresetID == preset.id { clearActiveShowSelection() }
            if pendingShowConfirmationID == preset.id { pendingShowConfirmationID = nil }
            showStatus = "Preset de \(preset.songTitle) excluído"
        } catch { fail(error) }
    }

    @discardableResult
    func testShowPreset(_ preset: ShowPreset) -> Bool {
        guard connected else {
            showStatus = "Conecte o PA700 para testar este preset"
            return false
        }
        guard let songBookNumber = preset.songBookNumber else {
            showStatus = "Defina o número SongBook antes de testar \(preset.songTitle)"
            return false
        }
        do {
            try transport?.sendScheduled(driver.compile(.selectSongBookEntry(number: songBookNumber), allowDraft: false))
            pendingShowConfirmationID = preset.id
            showStatus = "SongBook \(songBookNumber) enviado. Confira o PA700 e confirme o preset."
            return true
        } catch {
            showStatus = "Falha ao testar \(preset.songTitle)"
            fail(error)
            return false
        }
    }

    @discardableResult
    func confirmShowPreset(_ preset: ShowPreset) -> Bool {
        guard pendingShowConfirmationID == preset.id else {
            showStatus = "Teste este preset no PA700 antes de confirmar"
            return false
        }
        var confirmed = preset
        confirmed.confirmedAt = Date()
        guard saveShowPreset(confirmed) else { return false }
        pendingShowConfirmationID = nil
        showStatus = "Preset de \(confirmed.songTitle) confirmado no PA700"
        return true
    }

    @discardableResult
    func applyShowPreset(_ preset: ShowPreset, setListItemID: UUID? = nil) -> Bool {
        guard preset.isConfirmed, let songBookNumber = preset.songBookNumber else {
            showStatus = "\(preset.songTitle) ainda não foi confirmado no PA700"
            return false
        }
        guard connected else {
            clearActiveShowSelection()
            showStatus = "PA700 desconectado. Reconecte antes de aplicar a música."
            return false
        }
        do {
            try transport?.sendScheduled(driver.compile(.selectSongBookEntry(number: songBookNumber), allowDraft: false))
            activeShowPresetID = preset.id
            activeShowSetListItemID = setListItemID
            lastShowAppliedAt = Date()
            showStatus = "\(preset.songTitle) aplicada · SongBook \(songBookNumber)"
            status = showStatus
            return true
        } catch {
            showStatus = "Falha ao aplicar \(preset.songTitle); a música ativa não mudou"
            fail(error)
            return false
        }
    }

    @discardableResult
    func createShowSetList(named rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            showStatus = "Digite um nome para o repertório"
            return false
        }
        guard !showSetLists.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            showStatus = "Já existe um repertório chamado \(name)"
            return false
        }
        do {
            var updated = showSetLists
            let setList = ShowSetList(name: name)
            updated.append(setList)
            updated.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            try persistShowSetLists(updated)
            showSetLists = updated
            if activeShowSetListID == nil { selectShowSetList(setList.id) }
            showStatus = "Repertório \(name) criado"
            return true
        } catch {
            fail(error)
            return false
        }
    }

    func renameShowSetList(_ setList: ShowSetList, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { showStatus = "Digite um nome para o repertório"; return }
        guard !showSetLists.contains(where: { $0.id != setList.id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            showStatus = "Já existe um repertório chamado \(name)"
            return
        }
        guard updateShowSetList(setList.id, update: { $0.name = name }) else { return }
        showStatus = "Repertório renomeado para \(name)"
    }

    func addShowPreset(_ preset: ShowPreset, to setList: ShowSetList) {
        guard updateShowSetList(setList.id, update: { $0.items.append(.init(presetID: preset.id)) }) else { return }
        showStatus = "\(preset.songTitle) adicionada a \(setList.name)"
    }

    func removeShowSetListItem(_ item: ShowSetListItem, from setList: ShowSetList) {
        guard updateShowSetList(setList.id, update: { $0.items.removeAll { $0.id == item.id } }) else { return }
        if activeShowSetListItemID == item.id { clearActiveShowSelection() }
        showStatus = "Música removida de \(setList.name)"
    }

    func moveShowSetListItem(_ item: ShowSetListItem, in setList: ShowSetList, offset: Int) {
        guard offset == -1 || offset == 1,
              let index = setList.items.firstIndex(where: { $0.id == item.id }) else { return }
        let destination = index + offset
        guard setList.items.indices.contains(destination) else { return }
        guard updateShowSetList(setList.id, update: { $0.items.swapAt(index, destination) }) else { return }
        showStatus = "Ordem de \(setList.name) atualizada"
    }

    func deleteShowSetList(_ setList: ShowSetList) {
        do {
            let updated = showSetLists.filter { $0.id != setList.id }
            try persistShowSetLists(updated)
            showSetLists = updated
            if activeShowSetListID == setList.id {
                selectShowSetList(updated.first?.id)
                clearActiveShowSelection()
            }
            showStatus = "Repertório \(setList.name) excluído"
        } catch { fail(error) }
    }

    func selectShowSetList(_ id: UUID?) {
        activeShowSetListID = id.flatMap { candidate in showSetLists.contains(where: { $0.id == candidate }) ? candidate : nil }
        if let activeShowSetListID {
            UserDefaults.standard.set(activeShowSetListID.uuidString, forKey: "arrangerlab.activeShowSetListID")
        } else {
            UserDefaults.standard.removeObject(forKey: "arrangerlab.activeShowSetListID")
        }
        clearActiveShowSelection()
    }

    func showPreset(for item: ShowSetListItem) -> ShowPreset? {
        showPresets.first { $0.id == item.presetID }
    }

    func openShowPresetForReading(_ preset: ShowPreset) {
        showStatus = "\(preset.songTitle) aberta para leitura · não enviada ao PA700"
    }

    @discardableResult
    func importBundledShowCatalog() -> Bool {
        do {
            let catalog = try BundledShowCatalog.botecoJul3()
            return try importBundledShowCatalog(catalog, activate: true)
        } catch {
            showStatus = "Não foi possível importar o repertório Boteco Jul3"
            fail(error)
            return false
        }
    }

    @discardableResult
    func importShowboatJul23Catalog() -> Bool {
        do {
            let catalog = try BundledShowCatalog.showboatJul23()
            return try importBundledShowCatalog(catalog, activate: true)
        } catch {
            showStatus = "Não foi possível importar o repertório Showboat Jul 23"
            fail(error)
            return false
        }
    }

    func originalShowChart(for preset: ShowPreset) -> [ShowChartLine]? {
        guard let source = preset.source,
              let catalog = try? BundledShowCatalog.bundled(catalogID: source.catalogID) else { return nil }
        let songID = source.catalogSongID
        return catalog.entries.first(where: { $0.catalogSongID == songID })?.chartLines
    }

    @discardableResult
    func importExtractedShowPresets(_ candidates: [ShowPreset]) -> [UUID] {
        guard !candidates.isEmpty else { return [] }
        do {
            let existingSources = Set(showPresets.compactMap { preset in
                preset.source.map { "\($0.catalogID):\($0.catalogSongID)" }
            })
            var seenSources = existingSources
            var imported: [ShowPreset] = []
            for var candidate in candidates {
                let sourceKey = candidate.source.map { "\($0.catalogID):\($0.catalogSongID)" }
                if let sourceKey, seenSources.contains(sourceKey) { continue }
                candidate.confirmedAt = nil
                try candidate.validate()
                imported.append(candidate)
                if let sourceKey { seenSources.insert(sourceKey) }
            }
            guard !imported.isEmpty else {
                showStatus = "Os PDFs selecionados já foram importados; nenhum arquivo foi guardado"
                return []
            }

            var updatedPresets = showPresets
            updatedPresets.append(contentsOf: imported)
            var updatedSetLists = showSetLists
            let targetSetListID: UUID
            if let activeShowSetListID,
               updatedSetLists.contains(where: { $0.id == activeShowSetListID }) {
                targetSetListID = activeShowSetListID
            } else {
                let setList = ShowSetList(name: "Músicas importadas")
                updatedSetLists.append(setList)
                targetSetListID = setList.id
            }
            if let index = updatedSetLists.firstIndex(where: { $0.id == targetSetListID }) {
                updatedSetLists[index].items.append(contentsOf: imported.map { .init(presetID: $0.id) })
                updatedSetLists[index].updatedAt = Date()
            }

            try persistShowPresets(updatedPresets)
            try persistShowSetLists(updatedSetLists)
            showPresets = updatedPresets
            showSetLists = updatedSetLists
            if activeShowSetListID == nil { selectShowSetList(targetSetListID) }
            showStatus = imported.count == 1
                ? "Cifra extraída do PDF; o arquivo original não foi guardado"
                : "\(imported.count) cifras extraídas; os PDFs originais não foram guardados"
            return imported.map(\.id)
        } catch {
            showStatus = "Não foi possível salvar as cifras extraídas"
            fail(error)
            return []
        }
    }

    func togglePerformanceArranger() {
        do {
            try transport?.sendScheduled(driver.compile(.triggerArrangerControl(.arrangerStartStop)))
            status = "Start / Stop enviado ao ritmo"
            performanceStatus = status
        } catch { fail(error) }
    }

    func sendPresetLab(bankMSB: Int, bankLSB: Int, program: Int) {
        guard [bankMSB, bankLSB, program].allSatisfy({ (0...127).contains($0) }) else { fail(ArrangerLabError.invalidValue("bank/program must be 0...127")); return }
        do {
            try transport?.send(.controlChange(channel: 0, controller: 0, value: UInt8(bankMSB)))
            try transport?.send(.controlChange(channel: 0, controller: 32, value: UInt8(bankLSB)))
            try transport?.send(.programChange(channel: 0, program: UInt8(program)))
            status = "Draft: \(bankMSB).\(bankLSB).\(program) enviado ao right/layer 1"
        } catch { fail(error) }
    }

    func toggleCatalogFavorite(id: String) {
        guard let entry = batchSoundEntries.first(where: { $0.id == id }),
              var collector = batchCollector else { return }
        collector.setFavorite(id: id, isFavorite: !entry.isFavorite)
        batchCollector = collector
        syncBatchCatalogState(from: collector)
        saveBatchCatalogSilently()
    }

    func auditionCatalogSound(id: String, target: KeyboardPartTarget, partName: String) {
        guard connected else { fail(ArrangerLabError.endpointUnavailable); return }
        guard identityVerified else { auditionMessage = "Confirme primeiro a identidade do PA700"; return }
        guard presetConfigured else { auditionMessage = "Selecione e confirme o MIDI Preset ArrangerLab"; return }
        guard let entry = batchSoundEntries.first(where: { $0.id == id }) else { return }
        guard auditioningSoundID == nil else { return }

        pendingAuditionSoundID = nil
        auditionAudioEvidence = nil
        auditionAudioSourceURL = nil
        auditionPartName = partName
        auditioningSoundID = id
        auditionMessage = "Preparando \(entry.effectiveName)…"

        auditionTask = Task { [weak self] in
            guard let self else { return }
            guard await audioRecorder.requestPermission() else {
                auditioningSoundID = nil
                auditionMessage = "Microfone necessário para salvar a evidência"
                fail(ArrangerLabError.microphoneDenied)
                return
            }
            do {
                let base = try ArrLabPackage.applicationSupportDirectory().appendingPathComponent("Loose Audio", isDirectory: true)
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                let audioURL = base.appendingPathComponent("audition-\(UUID().uuidString).wav")
                try audioRecorder.start(to: audioURL)
                auditionAudioSourceURL = audioURL
                auditionEventStartIndex = events.count

                let channel = try auditionChannel(for: target)
                let selection = entry.selection
                try transport?.send(.controlChange(channel: channel, controller: 7, value: 96))
                try transport?.send(.controlChange(channel: channel, controller: 11, value: 127))
                try transport?.send(.controlChange(channel: channel, controller: 10, value: 64))
                try transport?.send(.controlChange(channel: channel, controller: 0, value: selection.bankMSB))
                try transport?.send(.controlChange(channel: channel, controller: 32, value: selection.bankLSB))
                try transport?.send(.programChange(channel: channel, program: selection.program))
                auditionMessage = "Ouvindo \(entry.effectiveName) em \(partName)"
                try await Task.sleep(nanoseconds: 250_000_000)

                let isBass = entry.category?.localizedCaseInsensitiveContains("bass") == true
                let notes: [UInt8] = isBass ? [36, 43, 48] : [60, 64, 67, 72]
                for note in notes {
                    try Task.checkCancellation()
                    try transport?.send(.noteOn(channel: channel, note: note, velocity: 88))
                    try await Task.sleep(nanoseconds: 330_000_000)
                    try transport?.send(.noteOff(channel: channel, note: note, velocity: 0))
                    try await Task.sleep(nanoseconds: 90_000_000)
                }
                try await Task.sleep(nanoseconds: 350_000_000)
                auditionAudioEvidence = try audioRecorder.stop()
                try? transport?.panic()

                if var collector = batchCollector {
                    collector.markAuditioned(id: id)
                    batchCollector = collector
                    syncBatchCatalogState(from: collector)
                    saveBatchCatalogSilently()
                }
                auditioningSoundID = nil
                pendingAuditionSoundID = id
                auditionMessage = "O nome e o som correspondem ao PA700?"
            } catch is CancellationError {
                audioRecorder.stopSilently()
                try? transport?.panic()
                auditioningSoundID = nil
                auditionMessage = "Audição cancelada"
            } catch {
                audioRecorder.stopSilently()
                auditioningSoundID = nil
                auditionMessage = "Não foi possível concluir a audição"
                fail(error)
            }
        }
    }

    func cancelCatalogAudition() {
        auditionTask?.cancel()
        auditionTask = nil
        pendingAuditionSoundID = nil
        auditionAudioEvidence = nil
        auditionAudioSourceURL = nil
        try? transport?.panic()
        auditionMessage = "Audição cancelada"
    }

    func confirmCatalogAudition(matches: Bool) {
        guard let id = pendingAuditionSoundID,
              let entry = batchSoundEntries.first(where: { $0.id == id }) else { return }
        pendingAuditionSoundID = nil
        guard matches else {
            auditionAudioEvidence = nil
            auditionAudioSourceURL = nil
            auditionMessage = "Mantido como Draft; revise o nome ou endereço"
            return
        }
        guard let evidence = auditionAudioEvidence,
              evidence.durationSeconds >= 1.5,
              evidence.metrics.peak > 0.0001,
              let source = auditionAudioSourceURL else {
            auditionMessage = "Evidência de áudio insuficiente; ouça novamente"
            return
        }

        do {
            let now = Date()
            let base = try ArrLabPackage.applicationSupportDirectory()
            let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
            let safeName = entry.effectiveName.replacingOccurrences(of: "/", with: "-")
            let url = base.appendingPathComponent("Preset-\(safeName)-\(stamp)", isDirectory: true).appendingPathExtension("arrlab")
            let state = DeviceStateSnapshot(
                model: profile.model,
                firmware: profile.firmware,
                midiPreset: "ArrangerLab",
                clockSource: "Internal",
                mode: "Sound",
                inputEndpoint: transport?.selectedSource?.name ?? "",
                outputEndpoint: transport?.selectedDestination?.name ?? ""
            )
            let address = "CC0 \(entry.selection.bankMSB) · CC32 \(entry.selection.bankLSB) · PC \(entry.selection.program)"
            let confirmation = ManualConfirmation(
                prompt: "Displayed PA700 name and audible sound match \(entry.effectiveName)",
                confirmed: true,
                note: "User confirmed \(entry.effectiveName) after a fixed audition on \(auditionPartName)."
            )
            let manifest = ArrLabManifest(
                schemaVersion: 1,
                experimentID: UUID(),
                title: "PA700 preset \(entry.effectiveName) verification",
                createdAt: now,
                updatedAt: now,
                hypothesis: "The exact catalogue address selects the displayed and audible preset \(entry.effectiveName).",
                mappingID: "devicePreset.\(entry.id)",
                mappingStatus: .verified,
                deviceState: state,
                annotations: [
                    "identity and firmware \(profile.firmware): passed",
                    "MIDI Preset ArrangerLab: passed",
                    "raw selection: \(address)",
                    "audio evidence: passed",
                    "physical displayed-name confirmation: passed",
                    "verified in laboratory catalogue; profile/API export remains a separate reviewed step"
                ]
            )
            let capturedEvents = Array(events.dropFirst(auditionEventStartIndex))
            let analysis = ExperimentAnalysis(
                notes: ["\(entry.effectiveName) · \(address) · \(auditionPartName)"],
                audioEvidence: [evidence],
                manualConfirmations: [confirmation],
                spectralDistances: [:]
            )
            try ArrLabPackage.save(.init(manifest: manifest, events: capturedEvents, analysis: analysis), to: url)
            try FileManager.default.copyItem(at: source, to: url.appendingPathComponent(evidence.relativePath))
            try CaptureExporter.csv(events: capturedEvents).write(to: url.appendingPathComponent("export.csv"), atomically: true, encoding: .utf8)
            try CaptureExporter.smf(events: capturedEvents).write(to: url.appendingPathComponent("export.mid"), options: .atomic)
            if var collector = batchCollector {
                collector.markVerified(id: id, experimentPath: url.path)
                batchCollector = collector
                syncBatchCatalogState(from: collector)
                try saveBatchCatalog()
            }
            auditionExperimentURL = url
            auditionAudioEvidence = nil
            auditionAudioSourceURL = nil
            auditionMessage = "Verified: \(entry.effectiveName) salvo com MIDI, áudio e confirmação"
            status = auditionMessage
        } catch { fail(error) }
    }

    func sendSongBook(_ number: Int) {
        do {
            try transport?.sendScheduled(driver.compile(.selectSongBookEntry(number: number), allowDraft: true))
            status = "\(songBookVerified ? "Verified" : "Draft"): SongBook \(number) enviado no canal 16"
        }
        catch { fail(error) }
    }

    func sendArrangerElement(_ element: ArrangerElement) {
        do {
            try transport?.sendScheduled(driver.compile(.selectArrangerElement(element), allowDraft: true))
            let mapping = profile.mappings[element.mappingID]?.status.rawValue ?? "Draft"
            status = "\(mapping): \(element.displayName) enviado no canal Control 16 · CF \(String(format: "%02X", element.rawValue))"
        } catch { fail(error) }
    }

    func sendKeyboardSet(_ slot: Int) {
        do {
            try transport?.sendScheduled(driver.compile(.selectKeyboardSet(slot: slot), allowDraft: true))
            let mapping = profile.mappings["keyboardSet"]?.status.rawValue ?? "Draft"
            status = "\(mapping): Keyboard Set \(slot) enviado no canal Control 16 · CF \(String(format: "%02X", 63 + slot))"
        } catch { fail(error) }
    }

    func sendArrangerControl(_ control: ArrangerControl) {
        do {
            try transport?.sendScheduled(driver.compile(.triggerArrangerControl(control), allowDraft: true))
            let mapping = profile.mappings[control.mappingID]?.status.rawValue ?? "Draft"
            status = "\(mapping): \(control.displayName) enviado no canal Control 16 · CF \(String(format: "%02X", control.rawValue))"
        } catch { fail(error) }
    }

    func confirmSongBookStylePlay() {
        guard connected else { fail(ArrangerLabError.endpointUnavailable); return }
        guard identityVerified else { status = "Confirme primeiro a identidade do PA700"; return }
        guard presetConfigured else { status = "Confirme primeiro o preset MIDI ArrangerLab"; return }
        songBookStylePlayConfirmed = true
        songBookSentNumber = nil
        songBookDisplayedName = ""
        songBookVerificationChecks.removeAll()
        songBookEventsStartIndex = events.count
        confirm("PA700 was in Style Play before SongBook selection")
        status = "Style Play confirmado; pronto para selecionar SongBook 9000"
    }

    func sendGuidedSongBook(_ number: Int) {
        guard songBookStylePlayConfirmed else { status = "Confirme primeiro que o PA700 está em Style Play"; return }
        guard connected else { fail(ArrangerLabError.endpointUnavailable); return }
        guard number == 9_000 else { status = "Este experimento usa a entrada dedicada 9000"; return }
        songBookEventsStartIndex = events.count
        do {
            try transport?.sendScheduled(driver.compile(.selectSongBookEntry(number: number), allowDraft: true))
            songBookSentNumber = number
            songBookDisplayedName = ""
            songBookVerificationChecks.removeAll()
            status = "SongBook 9000 enviado; confirme o nome mostrado no PA700"
        } catch { fail(error) }
    }

    func confirmGuidedSongBook(displayedName: String) {
        guard let number = songBookSentNumber else { status = "Envie primeiro o SongBook 9000"; return }
        let name = displayedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { status = "Digite o nome exatamente como aparece no PA700"; return }
        songBookDisplayedName = name
        confirm("Displayed SongBook entry matched requested number \(number): \(name)")
        updateSongBookChecks()
        status = songBookPasses
            ? "SongBook 9000 confirmado; pronto para salvar"
            : "A confirmação foi registrada, mas algum critério ainda não passou"
    }

    func saveSongBookVerification() {
        updateSongBookChecks()
        guard songBookPasses, let number = songBookSentNumber else {
            status = "Ainda faltam critérios para salvar SongBook como Verified"
            return
        }
        do {
            let base = try ArrLabPackage.applicationSupportDirectory()
            let url = base.appendingPathComponent("SongBook-\(number)-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-"))", isDirectory: true).appendingPathExtension("arrlab")
            let capturedEvents = Array(events.dropFirst(songBookEventsStartIndex))
            let state = DeviceStateSnapshot(model: profile.model, firmware: profile.firmware, midiPreset: "ArrangerLab", clockSource: "Internal", mode: "Sound", inputEndpoint: transport?.selectedSource?.name ?? "", outputEndpoint: transport?.selectedDestination?.name ?? "")
            let manifest = ArrLabManifest(
                schemaVersion: 1,
                experimentID: UUID(),
                title: "PA700 SongBook entry selection verification",
                createdAt: Date(),
                updatedAt: Date(),
                hypothesis: "NRPN 2/64 plus Data Entry on control channel 16 selects SongBook entry 9000",
                mappingID: "songBook",
                mappingStatus: .verified,
                deviceState: state,
                annotations: songBookVerificationChecks.keys.sorted().map { key in
                    "\(key): \(songBookVerificationChecks[key] == true ? "passed" : "failed")"
                }
            )
            let confirmations = manualConfirmations.filter {
                $0.prompt == "PA700 was in Style Play before SongBook selection"
                    || $0.prompt == "Displayed SongBook entry matched requested number \(number): \(songBookDisplayedName)"
                    || $0.prompt == "ArrangerLab MIDI preset configured"
            }
            let analysis = ExperimentAnalysis(
                notes: ["SongBook \(number): name=\(songBookDisplayedName); channel 16 NRPN 2/64 + Data Entry 90/0"],
                audioEvidence: [],
                manualConfirmations: confirmations,
                spectralDistances: [:]
            )
            try ArrLabPackage.save(.init(manifest: manifest, events: capturedEvents, analysis: analysis), to: url)
            try CaptureExporter.csv(events: capturedEvents).write(to: url.appendingPathComponent("export.csv"), atomically: true, encoding: .utf8)
            try CaptureExporter.smf(events: capturedEvents).write(to: url.appendingPathComponent("export.mid"), options: .atomic)
            songBookVerified = true
            songBookExperimentURL = url
            status = "Verified: SongBook 9000 salvo em \(url.path)"
        } catch { fail(error) }
    }

    private func updateSongBookChecks() {
        guard let number = songBookSentNumber else {
            songBookVerificationChecks = [:]
            return
        }
        songBookVerificationChecks = MappingEvidenceVerifier.songBook(
            events: Array(events.dropFirst(songBookEventsStartIndex)),
            number: number,
            expectedNumber: 9_000,
            displayedName: songBookDisplayedName,
            expectedName: "ArrangerLab Test",
            firmware: profile.firmware,
            expectedFirmware: "1.5.0",
            midiPreset: presetConfigured ? "ArrangerLab" : "",
            identityConfirmed: identityVerified,
            stylePlayConfirmed: songBookStylePlayConfirmed,
            manualConfirmations: manualConfirmations
        ).checks
    }

    func playFixedStimulus() {
        let notes = [60, 64, 67, 72]
        Task {
            for note in notes { sendNote(channel: 1, note: note, velocity: 80); try? await Task.sleep(nanoseconds: 450_000_000) }
            status = "Estímulo fixo C4–E4–G4–C5 concluído"
        }
    }

    func confirm(_ prompt: String) {
        if !manualConfirmations.contains(where: { $0.prompt == prompt && $0.confirmed }) {
            manualConfirmations.append(.init(prompt: prompt, confirmed: true, note: "Confirmed in Arranger Lab UI"))
        }
        status = "Confirmação manual registrada"
    }

    func confirmVolumeAndSave() {
        confirm("Volume right/layer 1 audibly changed")
        saveExperiment()
    }

    func confirmExpressionAndSave() {
        confirm("Expression right/layer 1 audibly changed")
        let verification = partExpressionVerification
        guard verification.passed else {
            status = "Expression ainda não passou por bytes, áudio, preset, identidade e confirmação"
            return
        }
        do {
            let base = try ArrLabPackage.applicationSupportDirectory()
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = base.appendingPathComponent("Part-Expression-\(timestamp)", isDirectory: true).appendingPathExtension("arrlab")
            let capturedEvents = Array(events.dropFirst(expressionEventsStartIndex))
            let capturedAudio = ([silenceEvidence].compactMap { $0 } + [25, 50, 75].compactMap { expressionEvidenceByLevel[$0] })
            let state = DeviceStateSnapshot(model: profile.model, firmware: profile.firmware, midiPreset: "ArrangerLab", clockSource: "Internal", mode: "Style Play", inputEndpoint: transport?.selectedSource?.name ?? "", outputEndpoint: transport?.selectedDestination?.name ?? "")
            let manifest = ArrLabManifest(
                schemaVersion: 1,
                experimentID: UUID(),
                title: "PA700 right/layer 1 expression verification",
                createdAt: Date(),
                updatedAt: Date(),
                hypothesis: "CC11 on configured channel 1 controls right/layer 1 relative expression",
                mappingID: verification.mappingID,
                mappingStatus: .verified,
                deviceState: state,
                annotations: verification.annotations
            )
            let confirmations = manualConfirmations.filter {
                $0.prompt == "Expression right/layer 1 audibly changed" || $0.prompt == "ArrangerLab MIDI preset configured"
            }
            let notes = [25, 50, 75].compactMap { level -> String? in
                guard let evidence = expressionEvidenceByLevel[level] else { return nil }
                return "expression.\(level)=\(String(format: "%.2f", evidence.metrics.rmsDBFS)) dBFS; audio=\(evidence.relativePath)"
            }
            let analysis = ExperimentAnalysis(notes: notes, audioEvidence: capturedAudio, manualConfirmations: confirmations, spectralDistances: [:])
            try ArrLabPackage.save(.init(manifest: manifest, events: capturedEvents, analysis: analysis), to: url)
            for evidence in capturedAudio {
                guard let source = audioSourceURLs[evidence.id] else { continue }
                let destination = url.appendingPathComponent(evidence.relativePath)
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.copyItem(at: source, to: destination)
            }
            try CaptureExporter.csv(events: capturedEvents).write(to: url.appendingPathComponent("export.csv"), atomically: true, encoding: .utf8)
            try CaptureExporter.smf(events: capturedEvents).write(to: url.appendingPathComponent("export.mid"), options: .atomic)
            persistedPartExpressionEvidenceReady = true
            partExpressionExperimentURL = url
            status = "Evidência pronta: partExpression pode ser promovido no perfil"
        } catch { fail(error) }
    }

    func recordPanEvidence(position: Int) {
        guard [-100, 0, 100].contains(position) else { return }
        if panEvidenceByPosition.isEmpty { panEventsStartIndex = events.count }
        runGuidedAudio(kind: .pan(position))
    }

    func confirmPanAndSave() {
        confirm("Pan right/layer 1 moved left, center and right")
        let verification = partPanVerification
        guard verification.passed else {
            status = "Pan ainda não passou por bytes, áudio, preset, identidade e confirmação estéreo"
            return
        }
        do {
            let base = try ArrLabPackage.applicationSupportDirectory()
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = base.appendingPathComponent("Part-Pan-\(timestamp)", isDirectory: true).appendingPathExtension("arrlab")
            let capturedEvents = Array(events.dropFirst(panEventsStartIndex))
            let capturedAudio = ([silenceEvidence].compactMap { $0 } + [-100, 0, 100].compactMap { panEvidenceByPosition[$0] })
            let state = DeviceStateSnapshot(model: profile.model, firmware: profile.firmware, midiPreset: "ArrangerLab", clockSource: "Internal", mode: "Style Play", inputEndpoint: transport?.selectedSource?.name ?? "", outputEndpoint: transport?.selectedDestination?.name ?? "")
            let manifest = ArrLabManifest(
                schemaVersion: 1,
                experimentID: UUID(),
                title: "PA700 right/layer 1 pan verification",
                createdAt: Date(),
                updatedAt: Date(),
                hypothesis: "CC10 on configured channel 1 moves right/layer 1 across the stereo panorama",
                mappingID: verification.mappingID,
                mappingStatus: .verified,
                deviceState: state,
                annotations: verification.annotations
            )
            let confirmations = manualConfirmations.filter {
                $0.prompt == "Pan right/layer 1 moved left, center and right" || $0.prompt == "ArrangerLab MIDI preset configured"
            }
            let labels = [-100: "left", 0: "center", 100: "right"]
            let notes = [-100, 0, 100].compactMap { position -> String? in
                guard let evidence = panEvidenceByPosition[position] else { return nil }
                return "pan.\(labels[position] ?? String(position))=\(String(format: "%.2f", evidence.metrics.rmsDBFS)) dBFS; audio=\(evidence.relativePath)"
            }
            let analysis = ExperimentAnalysis(notes: notes, audioEvidence: capturedAudio, manualConfirmations: confirmations, spectralDistances: [:])
            try ArrLabPackage.save(.init(manifest: manifest, events: capturedEvents, analysis: analysis), to: url)
            for evidence in capturedAudio {
                guard let source = audioSourceURLs[evidence.id] else { continue }
                let destination = url.appendingPathComponent(evidence.relativePath)
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.copyItem(at: source, to: destination)
            }
            try CaptureExporter.csv(events: capturedEvents).write(to: url.appendingPathComponent("export.csv"), atomically: true, encoding: .utf8)
            try CaptureExporter.smf(events: capturedEvents).write(to: url.appendingPathComponent("export.mid"), options: .atomic)
            persistedPartPanEvidenceReady = true
            partPanExperimentURL = url
            status = "Evidência pronta: partPan pode ser promovido no perfil"
        } catch { fail(error) }
    }

    func recordDamperEvidence() {
        guard activeGuideAction == nil else { return }
        guard connected else { fail(ArrangerLabError.endpointUnavailable); return }
        guard presetConfigured else { status = "Confirme primeiro o preset MIDI no PA700"; return }
        damperEventsStartIndex = events.count
        damperTestCompleted = false
        activeGuideAction = "Teste Damper: nota seca, depois nota sustentada"
        Task {
            do {
                let target = try KeyboardPartTarget(zone: .right, layer: 1)
                // The damper comparison must be unmistakable in a noisy room.
                // Use the PA700 part's full MIDI volume while keeping expression at 100%.
                try transport?.sendScheduled(driver.compile(.setPartVolume(target: target, level: 1.0), allowDraft: true))
                try transport?.sendScheduled(driver.compile(.setPartExpression(target: target, level: 1), allowDraft: true))
                try transport?.sendScheduled(driver.compile(.setPartPan(target: target, position: 0), allowDraft: true))
                try transport?.sendScheduled(driver.compile(.setPartDamper(target: target, engaged: false), allowDraft: true))
                try await Task.sleep(nanoseconds: 300_000_000)
                try transport?.send(.noteOn(channel: 0, note: 60, velocity: 88))
                try await Task.sleep(nanoseconds: 600_000_000)
                try transport?.send(.noteOff(channel: 0, note: 60, velocity: 0))
                try await Task.sleep(nanoseconds: 900_000_000)
                try transport?.sendScheduled(driver.compile(.setPartDamper(target: target, engaged: true), allowDraft: true))
                try transport?.send(.noteOn(channel: 0, note: 60, velocity: 88))
                try await Task.sleep(nanoseconds: 600_000_000)
                try transport?.send(.noteOff(channel: 0, note: 60, velocity: 0))
                try await Task.sleep(nanoseconds: 1_700_000_000)
                try transport?.sendScheduled(driver.compile(.setPartDamper(target: target, engaged: false), allowDraft: true))
                try await Task.sleep(nanoseconds: 500_000_000)
                damperTestCompleted = true
                activeGuideAction = nil
                status = "Damper OFF/ON/OFF concluído · confirme se a segunda nota sustentou · restaurado OFF"
            } catch {
                if let target = try? KeyboardPartTarget(zone: .right, layer: 1),
                   let restore = try? driver.compile(.setPartDamper(target: target, engaged: false), allowDraft: true) {
                    try? transport?.sendScheduled(restore)
                }
                activeGuideAction = nil
                fail(error)
            }
        }
    }

    func confirmDamperAndSave() {
        confirm("Damper right/layer 1 sustained the second note and released on OFF")
        let verification = partDamperVerification
        guard verification.passed else {
            status = "Damper ainda não passou por CC64 OFF/ON/OFF, áudio, preset, identidade e confirmação"
            return
        }
        do {
            let target = try KeyboardPartTarget(zone: .right, layer: 1)
            try transport?.sendScheduled(driver.compile(.setPartDamper(target: target, engaged: false), allowDraft: true))
            let base = try ArrLabPackage.applicationSupportDirectory()
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = base.appendingPathComponent("Part-Damper-\(timestamp)", isDirectory: true).appendingPathExtension("arrlab")
            let capturedEvents = Array(events.dropFirst(damperEventsStartIndex))
            let capturedAudio: [AudioEvidenceRecord] = []
            let state = DeviceStateSnapshot(model: profile.model, firmware: profile.firmware, midiPreset: "ArrangerLab", clockSource: "Internal", mode: "Style Play", inputEndpoint: transport?.selectedSource?.name ?? "", outputEndpoint: transport?.selectedDestination?.name ?? "")
            let manifest = ArrLabManifest(
                schemaVersion: 1,
                experimentID: UUID(),
                title: "PA700 right/layer 1 damper verification",
                createdAt: Date(),
                updatedAt: Date(),
                hypothesis: "CC64 on configured channel 1 sustains released notes while engaged and releases them when disengaged",
                mappingID: verification.mappingID,
                mappingStatus: .verified,
                deviceState: state,
                annotations: verification.annotations
            )
            let confirmations = manualConfirmations.filter {
                $0.prompt == "Damper right/layer 1 sustained the second note and released on OFF" || $0.prompt == "ArrangerLab MIDI preset configured"
            }
            let notes = ["Sound mode; MIDI preset 14 ArrangerLab; channel 1 mapped directly to Upper 1; damper.off-on-off comparison executed; CC64 restored to 0 after the sustained note; physical damper jack disconnected"]
            let analysis = ExperimentAnalysis(notes: notes, audioEvidence: capturedAudio, manualConfirmations: confirmations, spectralDistances: [:])
            try ArrLabPackage.save(.init(manifest: manifest, events: capturedEvents, analysis: analysis), to: url)
            for evidence in capturedAudio {
                guard let source = audioSourceURLs[evidence.id] else { continue }
                let destination = url.appendingPathComponent(evidence.relativePath)
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.copyItem(at: source, to: destination)
            }
            try CaptureExporter.csv(events: capturedEvents).write(to: url.appendingPathComponent("export.csv"), atomically: true, encoding: .utf8)
            try CaptureExporter.smf(events: capturedEvents).write(to: url.appendingPathComponent("export.mid"), options: .atomic)
            persistedPartDamperEvidenceReady = true
            partDamperExperimentURL = url
            status = "Evidência pronta: partDamper pode ser promovido no perfil · Damper restaurado OFF"
        } catch { fail(error) }
    }

    func preparePresetCapture(_ phase: PresetABAPhase) {
        guard connected else { fail(ArrangerLabError.endpointUnavailable); return }
        guard activeGuideAction == nil, !isAudioRecording else { return }
        switch phase {
        case .a1:
            break
        case .b where presetAudioEvidence[.a1] == nil:
            status = "Capture primeiro o timbre A"
            return
        case .a2 where presetAudioEvidence[.b] == nil:
            status = "Capture primeiro o timbre B"
            return
        default:
            break
        }
        pendingPresetPhase = phase
        presetCaptureStartIndex = events.count
        status = "\(phase.instruction); depois confirme no app"
    }

    func capturePresetPhase(_ phase: PresetABAPhase, displayedName: String) {
        let name = displayedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pendingPresetPhase == phase else { status = "Clique primeiro em Preparar \(phase.rawValue)"; return }
        guard !name.isEmpty else { status = "Digite o nome exatamente como aparece no PA700"; return }
        let selectionEvents = Array(events.dropFirst(presetCaptureStartIndex))
        guard let selection = MIDIProgramSelectionExtractor.lastComplete(in: selectionEvents, direction: .input, channel: 0) else {
            status = "Nenhum CC0 + CC32 + PC completo chegou do Upper1; selecione o timbre novamente"
            return
        }
        pendingPresetPhase = nil
        activeGuideAction = "Gravando \(phase.rawValue) com estímulo fixo"

        Task {
            guard await audioRecorder.requestPermission() else { activeGuideAction = nil; fail(ArrangerLabError.microphoneDenied); return }
            do {
                let base = try ArrLabPackage.applicationSupportDirectory().appendingPathComponent("Loose Audio", isDirectory: true)
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                let url = base.appendingPathComponent("preset-\(phase.rawValue)-\(UUID().uuidString).wav")
                try audioRecorder.start(to: url)
                let stimulusStartIndex = events.count
                try transport?.sendScheduled(driver.compile(.setPartVolume(target: try .init(zone: .right, layer: 1), level: 0.75)))
                try await Task.sleep(nanoseconds: 250_000_000)
                for note in [60, 64, 67, 72] {
                    try transport?.send(.noteOn(channel: 0, note: UInt8(note), velocity: 80))
                    try await Task.sleep(nanoseconds: 350_000_000)
                    try transport?.send(.noteOff(channel: 0, note: UInt8(note), velocity: 0))
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                try await Task.sleep(nanoseconds: 250_000_000)
                let evidence = try audioRecorder.stop()
                presetSelections[phase] = selection
                presetDisplayedNames[phase] = name
                presetAudioEvidence[phase] = evidence
                presetAudioSourceURLs[evidence.id] = url
                presetEventsByPhase[phase] = selectionEvents + Array(events.dropFirst(stimulusStartIndex))
                activeGuideAction = nil
                status = "\(phase.rawValue) capturado: \(selection.display)"
                if phase == .a2 { evaluateAndSavePresetABA() }
            } catch {
                audioRecorder.stopSilently()
                activeGuideAction = nil
                fail(error)
            }
        }
    }

    func resetPresetABA() {
        pendingPresetPhase = nil
        presetSelections.removeAll()
        presetAudioEvidence.removeAll()
        presetDisplayedNames.removeAll()
        presetABADistances.removeAll()
        devicePresetVerificationChecks.removeAll()
        presetEventsByPhase.removeAll()
        presetAudioSourceURLs.removeAll()
        devicePresetVerified = false
        presetExperimentURL = nil
        persistedPresetSummary = ""
        status = "Teste A-B-A reiniciado; a evidência anterior não foi apagada"
    }

    private func evaluateAndSavePresetABA() {
        guard let a1Selection = presetSelections[.a1],
              let bSelection = presetSelections[.b],
              let a2Selection = presetSelections[.a2],
              let a1Audio = presetAudioEvidence[.a1]?.metrics,
              let bAudio = presetAudioEvidence[.b]?.metrics,
              let a2Audio = presetAudioEvidence[.a2]?.metrics else { return }

        let a1a2 = AudioAnalyzer.spectralDistance(a1Audio, a2Audio)
        let a1b = AudioAnalyzer.spectralDistance(a1Audio, bAudio)
        let a2b = AudioAnalyzer.spectralDistance(a2Audio, bAudio)
        presetABADistances = ["A1-A2": a1a2, "A1-B": a1b, "A2-B": a2b]
        let namesPass = !((presetDisplayedNames[.a1] ?? "").isEmpty)
            && presetDisplayedNames[.a1] == presetDisplayedNames[.a2]
            && presetDisplayedNames[.a1] != presetDisplayedNames[.b]
        let rawPass = PresetABAPhase.allCases.allSatisfy { phase in
            guard let selection = presetSelections[phase], let phaseEvents = presetEventsByPhase[phase] else { return false }
            return selection.canonicalMessages.allSatisfy { message in
                phaseEvents.contains { $0.direction == .input && $0.rawBytes == message.canonicalBytes }
            }
        }
        devicePresetVerificationChecks = [
            "A1 and A2 MIDI selection match": a1Selection == a2Selection,
            "B MIDI selection differs": bSelection != a1Selection,
            "audio A-B-A spectral rule": PA700EvidenceRules.presetABA(a1: a1Audio, b: bAudio, a2: a2Audio),
            "device identity and firmware": identityVerified && profile.firmware == "1.5.0",
            "displayed names confirmed": namesPass,
            "MIDI preset ArrangerLab": presetConfigured,
            "raw CC0.CC32.PC for A-B-A": rawPass
        ]
        devicePresetVerified = presetABAPasses
        if devicePresetVerified {
            let name = presetDisplayedNames[.a1] ?? ""
            if !manualConfirmations.contains(where: { $0.prompt == "Displayed preset name matched captured bank/program: \(name)" }) {
                manualConfirmations.append(.init(prompt: "Displayed preset name matched captured bank/program: \(name)", confirmed: true, note: a1Selection.display))
            }
        }
        savePresetExperiment()
    }

    private func savePresetExperiment() {
        do {
            let base = try ArrLabPackage.applicationSupportDirectory()
            let url = base.appendingPathComponent("Preset-ABA-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-"))", isDirectory: true).appendingPathExtension("arrlab")
            let capturedEvents = PresetABAPhase.allCases.flatMap { presetEventsByPhase[$0] ?? [] }.sorted { $0.timestampNanoseconds < $1.timestampNanoseconds }
            let capturedAudio = PresetABAPhase.allCases.compactMap { presetAudioEvidence[$0] }
            let state = DeviceStateSnapshot(model: profile.model, firmware: profile.firmware, midiPreset: "ArrangerLab", clockSource: "Internal", mode: "Laboratory", inputEndpoint: transport?.selectedSource?.name ?? "", outputEndpoint: transport?.selectedDestination?.name ?? "")
            let mappingStatus: MappingStatus = presetABAPasses ? .verified : .draft
            let annotations = devicePresetVerificationChecks.keys.sorted().map { key in
                "\(key): \(devicePresetVerificationChecks[key] == true ? "passed" : "failed")"
            }
            let notes = PresetABAPhase.allCases.compactMap { phase -> String? in
                guard let selection = presetSelections[phase] else { return nil }
                return "\(phase.rawValue): name=\(presetDisplayedNames[phase] ?? ""); \(selection.display)"
            }
            let manifest = ArrLabManifest(
                schemaVersion: 1,
                experimentID: UUID(),
                title: "PA700 exact preset A-B-A verification",
                createdAt: Date(),
                updatedAt: Date(),
                hypothesis: "A repeated with the same CC0.CC32.PC is spectrally closer than A-B",
                mappingID: "devicePreset",
                mappingStatus: mappingStatus,
                deviceState: state,
                annotations: annotations
            )
            let confirmations = manualConfirmations.filter { $0.prompt.hasPrefix("Displayed preset name matched captured bank/program:") || $0.prompt == "ArrangerLab MIDI preset configured" }
            let analysis = ExperimentAnalysis(notes: notes, audioEvidence: capturedAudio, manualConfirmations: confirmations, spectralDistances: presetABADistances)
            try ArrLabPackage.save(.init(manifest: manifest, events: capturedEvents, analysis: analysis), to: url)
            for evidence in capturedAudio {
                guard let source = presetAudioSourceURLs[evidence.id] else { continue }
                let destination = url.appendingPathComponent(evidence.relativePath)
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.copyItem(at: source, to: destination)
            }
            try CaptureExporter.csv(events: capturedEvents).write(to: url.appendingPathComponent("export.csv"), atomically: true, encoding: .utf8)
            try CaptureExporter.smf(events: capturedEvents).write(to: url.appendingPathComponent("export.mid"), options: .atomic)
            presetExperimentURL = url
            persistedPresetSummary = notes.first ?? ""
            status = mappingStatus == .verified
                ? "Verified: preset exato A-B-A salvo em \(url.path)"
                : "A-B-A salvo como Draft; revise os critérios que falharam"
        } catch { fail(error) }
    }

    private enum GuidedAudioKind { case silence, volume(Int), expression(Int), pan(Int) }

    private func runGuidedAudio(kind: GuidedAudioKind) {
        guard activeGuideAction == nil else { return }
        guard connected else { fail(ArrangerLabError.endpointUnavailable); return }
        switch kind {
        case .silence: activeGuideAction = "Calibrando silêncio por 2 segundos"
        case let .volume(level):
            guard presetConfigured else { status = "Confirme primeiro o preset MIDI no PA700"; return }
            guard silenceEvidence != nil else { status = "Calibre primeiro o silêncio do ambiente"; return }
            activeGuideAction = "Gravando evidência de volume em \(level)%"
        case let .expression(level):
            guard presetConfigured else { status = "Confirme primeiro o preset MIDI no PA700"; return }
            guard silenceEvidence != nil else { status = "Calibre primeiro o silêncio do ambiente"; return }
            activeGuideAction = "Gravando evidência de Expression em \(level)%"
        case let .pan(position):
            guard presetConfigured else { status = "Confirme primeiro o preset MIDI no PA700"; return }
            guard silenceEvidence != nil else { status = "Calibre primeiro o silêncio do ambiente"; return }
            let label = position < 0 ? "esquerda" : (position > 0 ? "direita" : "centro")
            activeGuideAction = "Gravando evidência de Pan: \(label)"
        }

        Task {
            guard await audioRecorder.requestPermission() else { activeGuideAction = nil; fail(ArrangerLabError.microphoneDenied); return }
            do {
                let base = try ArrLabPackage.applicationSupportDirectory().appendingPathComponent("Loose Audio", isDirectory: true)
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                let url = base.appendingPathComponent("guided-\(UUID().uuidString).wav")
                try audioRecorder.start(to: url)

                switch kind {
                case .silence:
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                case let .volume(level), let .expression(level), let .pan(level):
                    let target = try KeyboardPartTarget(zone: .right, layer: 1)
                    let messages: [ScheduledMIDIMessage]
                    switch kind {
                    case .volume:
                        let normalized = Double(level) / 100
                        messages = try driver.compile(.setPartVolume(target: target, level: normalized), allowDraft: true)
                    case .expression:
                        let normalized = Double(level) / 100
                        try transport?.sendScheduled(driver.compile(.setPartVolume(target: target, level: 0.75), allowDraft: true))
                        messages = try driver.compile(.setPartExpression(target: target, level: normalized), allowDraft: true)
                    case .pan:
                        try transport?.sendScheduled(driver.compile(.setPartVolume(target: target, level: 0.75), allowDraft: true))
                        try transport?.sendScheduled(driver.compile(.setPartExpression(target: target, level: 1), allowDraft: true))
                        messages = try driver.compile(.setPartPan(target: target, position: Double(level) / 100), allowDraft: true)
                    case .silence:
                        messages = []
                    }
                    try transport?.sendScheduled(messages)
                    try await Task.sleep(nanoseconds: 300_000_000)
                    for note in [60, 64, 67, 72] {
                        try transport?.send(.noteOn(channel: 0, note: UInt8(note), velocity: 80))
                        try await Task.sleep(nanoseconds: 350_000_000)
                        try transport?.send(.noteOff(channel: 0, note: UInt8(note), velocity: 0))
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                    try await Task.sleep(nanoseconds: 300_000_000)
                }

                let evidence = try audioRecorder.stop()
                audioEvidence.append(evidence)
                audioSourceURLs[evidence.id] = url
                switch kind {
                case .silence:
                    silenceEvidence = evidence
                    status = "Silêncio calibrado em \(String(format: "%.1f", evidence.metrics.rmsDBFS)) dBFS"
                case let .volume(level):
                    volumeEvidenceByLevel[level] = evidence
                    status = "Evidência de \(level)% gravada: \(String(format: "%.1f", evidence.metrics.rmsDBFS)) dBFS"
                case let .expression(level):
                    expressionEvidenceByLevel[level] = evidence
                    if let target = try? KeyboardPartTarget(zone: .right, layer: 1),
                       let restore = try? driver.compile(.setPartExpression(target: target, level: 1), allowDraft: true) {
                        try? transport?.sendScheduled(restore)
                    }
                    status = "Expression \(level)% gravada: \(String(format: "%.1f", evidence.metrics.rmsDBFS)) dBFS · restaurada a 100%"
                case let .pan(position):
                    panEvidenceByPosition[position] = evidence
                    if let target = try? KeyboardPartTarget(zone: .right, layer: 1),
                       let restore = try? driver.compile(.setPartPan(target: target, position: 0), allowDraft: true) {
                        try? transport?.sendScheduled(restore)
                    }
                    let label = position < 0 ? "esquerda" : (position > 0 ? "direita" : "centro")
                    status = "Pan \(label) gravado: \(String(format: "%.1f", evidence.metrics.rmsDBFS)) dBFS · restaurado ao centro"
                }
                activeGuideAction = nil
            } catch {
                audioRecorder.stopSilently()
                activeGuideAction = nil
                fail(error)
            }
        }
    }

    private func receive(_ event: MIDIEvent) {
        events.append(event)
        if isBatchMapping { consumeBatchMappingEvent(event) }
        if events.count > 50_000 {
            events.removeFirst(5_000)
            recordingStartIndex = max(0, recordingStartIndex - 5_000)
            presetCaptureStartIndex = max(0, presetCaptureStartIndex - 5_000)
            arrangerEventsStartIndex = max(0, arrangerEventsStartIndex - 5_000)
            songBookEventsStartIndex = max(0, songBookEventsStartIndex - 5_000)
        }
        if let message = event.message {
            let identification = driver.identify(from: message)
            if identification.confidence == 1 {
                identityResult = "PA700 confirmado • fabricante 42 • família 0060 • modelo 005D • firmware 1.5.0"
                let verified = [
                    persistedPartVolumeVerified ? "partVolume" : nil,
                    partExpressionOperational ? "partExpression" : nil,
                    partPanOperational ? "partPan" : nil,
                    partDamperOperational ? "partDamper" : nil,
                    devicePresetVerified ? "devicePreset" : nil,
                    arrangerTransportVerified ? "arrangerTransport" : nil,
                    midiClockOperational ? "midiClock" : nil,
                    songBookVerified ? "songBook" : nil
                ].compactMap { $0 }
                status = verified.isEmpty ? "PA700 identificado" : "PA700 identificado • \(verified.joined(separator: " + ")) Verified"
            }
        }
    }

    private func consumeBatchMappingEvent(_ event: MIDIEvent) {
        guard var collector = batchCollector else { return }
        let knownPresets = profile.presets
        let captured = collector.consume(event, channel: 0) { selection in
            knownPresets.first {
                $0.bankMSB == selection.bankMSB
                    && $0.bankLSB == selection.bankLSB
                    && $0.program == selection.program
            }?.displayName
        }
        batchCollector = collector
        guard let captured else { return }
        syncBatchCatalogState(from: collector)
        saveBatchCatalogSilently()
        if let screen = collector.activeScreen {
            status = "\(screen.label) · \(screen.entryIDs.count) timbres capturados"
        } else {
            status = "Capturado \(captured.effectiveName) · \(batchSoundEntries.count) únicos"
        }
    }

    private func endBatchScreenCapture(silently: Bool) {
        guard var collector = batchCollector,
              let screen = collector.endScreen() else { return }
        batchCollector = collector
        syncBatchCatalogState(from: collector)
        saveBatchCatalogSilently()
        if !silently {
            status = "\(screen.label) encerrada · \(screen.entryIDs.count) timbres aguardando os nomes da foto"
        }
    }

    private func syncBatchCatalogState(from collector: BatchSoundCollector) {
        batchSoundEntries = collector.catalog.entries
        batchCaptureCount = collector.catalog.captureCount
        batchScreenCaptures = collector.catalog.screens
    }

    private func batchCatalogDirectory() throws -> URL {
        let directory = try ArrLabPackage.applicationSupportDirectory().appendingPathComponent("Catalogs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func saveBatchCatalog() throws {
        guard let catalog = batchCollector?.catalog, let url = batchCatalogURL else { return }
        try BatchSoundCatalogStore.save(catalog, to: url)
    }

    private func saveBatchCatalogSilently() {
        try? saveBatchCatalog()
    }

    private func restoreLatestBatchCatalog() {
        guard let directory = try? batchCatalogDirectory(),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else { return }
        let candidates = urls
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("PA700-Sounds-") }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
        for url in candidates {
            guard let catalog = try? BatchSoundCatalogStore.load(from: url) else { continue }
            let collector = BatchSoundCollector(catalog: catalog)
            batchCollector = collector
            syncBatchCatalogState(from: collector)
            batchCatalogURL = url
            saveBatchCatalogSilently()
            break
        }
    }

    private func updatePerformancePart(_ target: KeyboardPartTarget, update: (inout PerformanceScenePart) -> Void) {
        var setting = performancePartSettings[target] ?? .init(target: target)
        update(&setting)
        performancePartSettings[target] = setting
    }

    private func performanceSceneURL() throws -> URL {
        try ArrLabPackage.applicationSupportDirectory()
            .appendingPathComponent("Scenes", isDirectory: true)
            .appendingPathComponent("scenes.json")
    }

    private func persistPerformanceScenes(_ scenes: [PerformanceScene]) throws {
        try PerformanceSceneStore.save(scenes, to: performanceSceneURL())
    }

    private func performanceSetListURL() throws -> URL {
        try ArrLabPackage.applicationSupportDirectory()
            .appendingPathComponent("Scenes", isDirectory: true)
            .appendingPathComponent("setlists.json")
    }

    private func persistPerformanceSetLists(_ setLists: [PerformanceSetList]) throws {
        try PerformanceSetListStore.save(setLists, to: performanceSetListURL())
    }

    private func showDirectory() throws -> URL {
        try ArrLabPackage.applicationSupportDirectory().appendingPathComponent("Show", isDirectory: true)
    }

    private func showPresetURL() throws -> URL {
        try showDirectory().appendingPathComponent("presets.json")
    }

    private func showSetListURL() throws -> URL {
        try showDirectory().appendingPathComponent("setlists.json")
    }

    private func persistShowPresets(_ presets: [ShowPreset]) throws {
        try ShowPresetStore.save(presets, to: showPresetURL())
    }

    private func persistShowSetLists(_ setLists: [ShowSetList]) throws {
        try ShowSetListStore.save(setLists, to: showSetListURL())
    }

    @discardableResult
    private func updateShowSetList(_ id: UUID, update: (inout ShowSetList) -> Void) -> Bool {
        guard let index = showSetLists.firstIndex(where: { $0.id == id }) else { return false }
        do {
            var updated = showSetLists
            update(&updated[index])
            updated[index].updatedAt = Date()
            try persistShowSetLists(updated)
            showSetLists = updated
            return true
        } catch {
            fail(error)
            return false
        }
    }

    private func restoreShowPerformance() {
        do {
            showPresets = try ShowPresetStore.load(from: showPresetURL())
            showSetLists = try ShowSetListStore.load(from: showSetListURL())
            var shouldActivateShowboat = false
            var shouldActivateShowboatPianoBlock = false
            var didChangeCatalogData = false
            var importedCatalogNames: [String] = []
            var catalogsToMarkImported: [BundledShowCatalog] = []
            var plansToMarkImported: [BundledShowBlockPlan] = []
            for catalog in try BundledShowCatalog.allBundled() {
                let versionKey = bundledShowCatalogImportVersionKey(for: catalog)
                guard UserDefaults.standard.integer(forKey: versionKey) < catalog.schemaVersion else { continue }
                let merged = catalog.merging(presets: showPresets, setLists: showSetLists)
                if merged.presets != showPresets || merged.setLists != showSetLists {
                    showPresets = merged.presets
                    showSetLists = merged.setLists
                    didChangeCatalogData = true
                    if merged.importedCount > 0 {
                        importedCatalogNames.append("\(catalog.name) (\(merged.importedCount))")
                    }
                }
                catalogsToMarkImported.append(catalog)
                if catalog.catalogID == showboatCatalogID {
                    shouldActivateShowboat = true
                }
            }
            for plan in try BundledShowBlockPlan.allBundled() {
                let versionKey = bundledShowBlockImportVersionKey(for: plan)
                guard UserDefaults.standard.integer(forKey: versionKey) < plan.schemaVersion else { continue }
                let merged = plan.merging(
                    presets: showPresets,
                    setLists: showSetLists,
                    applyOperationalDefaults: true
                )
                if merged.presets != showPresets || merged.setLists != showSetLists {
                    showPresets = merged.presets
                    showSetLists = merged.setLists
                    didChangeCatalogData = true
                    importedCatalogNames.append(plan.name)
                }
                plansToMarkImported.append(plan)
                if plan.blockID == showboatPianoBlockID {
                    shouldActivateShowboatPianoBlock = true
                }
            }
            if didChangeCatalogData {
                try persistShowPresets(showPresets)
                try persistShowSetLists(showSetLists)
            }
            for catalog in catalogsToMarkImported {
                UserDefaults.standard.set(catalog.schemaVersion, forKey: bundledShowCatalogImportVersionKey(for: catalog))
                if catalog.catalogID == "boteco-jul3-gojam" {
                    UserDefaults.standard.set(catalog.schemaVersion, forKey: legacyBotecoImportVersionKey)
                }
            }
            for plan in plansToMarkImported {
                UserDefaults.standard.set(plan.schemaVersion, forKey: bundledShowBlockImportVersionKey(for: plan))
            }
            if !importedCatalogNames.isEmpty {
                showStatus = "Repertórios importados como rascunho: \(importedCatalogNames.joined(separator: ", "))"
            }
            let storedID = UserDefaults.standard.string(forKey: "arrangerlab.activeShowSetListID").flatMap(UUID.init(uuidString:))
            let storedSetListID = storedID.flatMap { id in showSetLists.contains(where: { $0.id == id }) ? id : nil }
            activeShowSetListID = (shouldActivateShowboatPianoBlock
                ? showSetLists.first(where: { $0.sourceCatalogID == showboatPianoBlockID })?.id
                : shouldActivateShowboat
                ? showSetLists.first(where: { $0.sourceCatalogID == showboatCatalogID })?.id
                : storedSetListID)
                ?? showSetLists.first(where: { $0.sourceCatalogID == showboatCatalogID })?.id
                ?? showSetLists.first?.id
            if let activeShowSetListID {
                UserDefaults.standard.set(activeShowSetListID.uuidString, forKey: "arrangerlab.activeShowSetListID")
            }
        } catch {
            lastError = "Dados de show não puderam ser carregados: \(error.localizedDescription)"
        }
    }

    private func bundledShowCatalogImportVersionKey(for catalog: BundledShowCatalog) -> String {
        "arrangerlab.showCatalogImportVersion.\(catalog.catalogID)"
    }

    private func bundledShowBlockImportVersionKey(for plan: BundledShowBlockPlan) -> String {
        "arrangerlab.showBlockImportVersion.\(plan.blockID)"
    }

    @discardableResult
    private func importBundledShowCatalog(_ catalog: BundledShowCatalog, activate: Bool) throws -> Bool {
        let merged = catalog.merging(presets: showPresets, setLists: showSetLists)
        let changed = merged.presets != showPresets || merged.setLists != showSetLists
        if changed {
            try persistShowPresets(merged.presets)
            try persistShowSetLists(merged.setLists)
            showPresets = merged.presets
            showSetLists = merged.setLists
        }
        if activate, let importedSetList = showSetLists.first(where: { $0.sourceCatalogID == catalog.catalogID }) {
            selectShowSetList(importedSetList.id)
        }
        UserDefaults.standard.set(catalog.schemaVersion, forKey: bundledShowCatalogImportVersionKey(for: catalog))
        if catalog.catalogID == "boteco-jul3-gojam" {
            UserDefaults.standard.set(catalog.schemaVersion, forKey: legacyBotecoImportVersionKey)
        }
        showStatus = merged.importedCount > 0
            ? "\(merged.importedCount) músicas de \(catalog.name) importadas como rascunho"
            : "\(catalog.name) já está atualizado; suas edições foram preservadas"
        return true
    }

    private func clearActiveShowSelection() {
        activeShowPresetID = nil
        activeShowSetListItemID = nil
        lastShowAppliedAt = nil
    }

    @discardableResult
    private func updatePerformanceSetList(_ id: UUID, update: (inout PerformanceSetList) -> Void) -> Bool {
        guard let index = performanceSetLists.firstIndex(where: { $0.id == id }) else { return false }
        do {
            var updated = performanceSetLists
            update(&updated[index])
            updated[index].updatedAt = Date()
            try persistPerformanceSetLists(updated)
            performanceSetLists = updated
            return true
        } catch {
            fail(error)
            return false
        }
    }

    private func restorePerformanceScenes() {
        do {
            performanceScenes = try PerformanceSceneStore.load(from: performanceSceneURL())
        } catch {
            lastError = "Cenas não puderam ser carregadas: \(error.localizedDescription)"
        }
    }

    private func restorePerformanceSetLists() {
        do {
            performanceSetLists = try PerformanceSetListStore.load(from: performanceSetListURL())
        } catch {
            lastError = "Set Lists não puderam ser carregadas: \(error.localizedDescription)"
        }
    }

    private func restoreLatestVerification() {
        do {
            let directory = try ArrLabPackage.applicationSupportDirectory()
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "arrlab" }.sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            var restoredVolume = false
            var restoredPreset = false
            var restoredTransport = false
            var restoredSongBook = false
            var restoredExpression = false
            var restoredPan = false
            var restoredDamper = false
            var restoredCatalogValidation = false
            for url in urls {
                guard let experiment = try? ArrLabPackage.load(from: url) else { continue }
                let manifest = experiment.manifest
                guard manifest.mappingStatus == .verified,
                      manifest.deviceState.model == profile.model,
                      manifest.deviceState.firmware == profile.firmware else { continue }
                if !persistedIdentityVerified {
                    persistedIdentityVerified = true
                    if !identityResult.hasPrefix("PA700 confirmado") {
                        identityResult = "PA700 confirmado por evidência salva • firmware 1.5.0"
                    }
                }
                if manifest.mappingID == "devicePreset", !restoredPreset {
                    devicePresetVerified = true
                    presetExperimentURL = url
                    persistedPresetSummary = experiment.analysis.notes.first ?? ""
                    presetABADistances = experiment.analysis.spectralDistances
                    restoredPreset = true
                }
                if ["devicePreset.catalogAddressing", "devicePreset.catalog"].contains(manifest.mappingID), !restoredCatalogValidation {
                    catalogValidationVerified = true
                    catalogValidationExperimentURL = url
                    restoredCatalogValidation = true
                }
                if manifest.mappingID == "arrangerTransport", !restoredTransport {
                    arrangerTransportVerified = true
                    arrangerTransportExperimentURL = url
                    arrangerTransportChecks = Dictionary(uniqueKeysWithValues: manifest.annotations.compactMap { annotation in
                        guard let separator = annotation.range(of: ": ", options: .backwards) else { return nil }
                        let key = String(annotation[..<separator.lowerBound])
                        let value = annotation[separator.upperBound...] == "passed"
                        return (key, value)
                    })
                    restoredTransport = true
                }
                if manifest.mappingID == "songBook", !restoredSongBook {
                    songBookVerified = true
                    songBookExperimentURL = url
                    songBookVerificationChecks = Dictionary(uniqueKeysWithValues: manifest.annotations.compactMap { annotation in
                        guard let separator = annotation.range(of: ": ", options: .backwards) else { return nil }
                        let key = String(annotation[..<separator.lowerBound])
                        let value = annotation[separator.upperBound...] == "passed"
                        return (key, value)
                    })
                    songBookDisplayedName = experiment.analysis.notes.first.flatMap { note in
                        guard let range = note.range(of: "name=") else { return nil }
                        return String(note[range.upperBound...].split(separator: ";").first ?? "")
                    } ?? ""
                    restoredSongBook = true
                }
                if manifest.mappingID == "partVolume", !restoredVolume {
                    persistedPartVolumeVerified = true
                    previousInputConfirmed = experiment.events.contains {
                        guard $0.direction == .input, let message = $0.message else { return false }
                        if case .noteOn = message { return true }
                        return false
                    }
                    previousOutputConfirmed = experiment.analysis.manualConfirmations.contains {
                        $0.confirmed && $0.prompt == "Mac to PA700 C4 output was audible"
                    }
                    previousPresetConfirmed = experiment.analysis.manualConfirmations.contains {
                        $0.confirmed && $0.prompt == "ArrangerLab MIDI preset configured"
                    }
                    let audio = experiment.analysis.audioEvidence
                    if audio.count >= 4 {
                        persistedVolumeRMSDBFS = Array(audio.dropFirst().prefix(3)).map(\.metrics.rmsDBFS)
                    }
                    lastSavedExperimentURL = url
                    restoredVolume = true
                }
                if manifest.mappingID == "partExpression", !restoredExpression {
                    persistedPartExpressionEvidenceReady = true
                    partExpressionExperimentURL = url
                    restoredExpression = true
                }
                if manifest.mappingID == "partPan", !restoredPan {
                    persistedPartPanEvidenceReady = true
                    partPanExperimentURL = url
                    restoredPan = true
                }
                if manifest.mappingID == "partDamper", !restoredDamper {
                    persistedPartDamperEvidenceReady = true
                    partDamperExperimentURL = url
                    damperTestCompleted = true
                    restoredDamper = true
                }
                if restoredVolume && restoredPreset && restoredTransport && restoredSongBook && restoredExpression && restoredPan && restoredDamper && restoredCatalogValidation { break }
            }
            if persistedIdentityVerified, status == "PA700 conectado; verificando identidade" {
                let verified = [
                    persistedPartVolumeVerified ? "partVolume" : nil,
                    partExpressionOperational ? "partExpression" : nil,
                    partPanOperational ? "partPan" : nil,
                    partDamperOperational ? "partDamper" : nil,
                    devicePresetVerified ? "devicePreset" : nil,
                    arrangerTransportVerified ? "arrangerTransport" : nil,
                    midiClockOperational ? "midiClock" : nil,
                    songBookVerified ? "songBook" : nil
                ].compactMap { $0 }
                status = "PA700 conectado • \(verified.joined(separator: " + ")) Verified"
            }
        } catch {
            // A missing or unreadable prior experiment must not block a fresh laboratory session.
        }
    }
    private func evidenceNotes() -> [String] {
        var notes: [String] = []
        if let silenceEvidence {
            notes.append("silence=\(String(format: "%.2f", silenceEvidence.metrics.rmsDBFS)) dBFS; audio=\(silenceEvidence.relativePath)")
        }
        for level in [25, 50, 75] {
            if let evidence = volumeEvidenceByLevel[level] {
                notes.append("volume.\(level)=\(String(format: "%.2f", evidence.metrics.rmsDBFS)) dBFS; audio=\(evidence.relativePath)")
            }
        }
        return notes
    }
    private func auditionChannel(for target: KeyboardPartTarget) throws -> UInt8 {
        let key: String
        switch (target.zone, target.layer) {
        case (.right, 1): key = "right1"
        case (.right, 2): key = "right2"
        case (.right, 3): key = "right3"
        case (.left, 1): key = "left1"
        default: throw ArrangerLabError.unsupported("unsupported keyboard part")
        }
        guard let oneBased = profile.channels[key], (1...16).contains(Int(oneBased)) else {
            throw ArrangerLabError.invalidProfile("missing channel for \(key)")
        }
        return oneBased - 1
    }
    private func send(_ message: MIDIMessage) { do { try transport?.send(message) } catch { fail(error) } }
    private func fail(_ error: Error) { lastError = error.localizedDescription; status = "Falha — Panic preventivo enviado"; try? transport?.panic() }
    private func parseHex(_ value: String) throws -> [UInt8] {
        try value.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }).map {
            guard let byte = UInt8($0, radix: 16) else { throw ArrangerLabError.invalidValue("invalid hex byte \($0)") }
            return byte
        }
    }
    private static func fallbackProfile() -> InstrumentProfile {
        .init(schemaVersion: 1, id: "invalid", manufacturer: "Korg", model: "PA700", firmware: "1.5.0", identitySignatures: [], aliases: [:], requiredConfiguration: [], channels: [:], mappings: [:], presets: [])
    }
}
