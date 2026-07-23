import ArrangerLabAudio
import ArrangerLabCore
import ArrangerLabMIDI
import CoreMIDI
import Foundation

struct HarnessFailure: Error, CustomStringConvertible { let description: String }
var passed = 0

func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
    guard condition() else { throw HarnessFailure(description: name) }
    passed += 1
    print("PASS  \(name)")
}

func event(_ message: MIDIMessage, at time: UInt64 = 1) -> MIDIEvent {
    .init(timestampNanoseconds: time, direction: .output, endpointUniqueID: 10, endpointName: "Test", rawBytes: message.canonicalBytes, message: message)
}

func inputEvent(_ message: MIDIMessage, at time: UInt64 = 1) -> MIDIEvent {
    .init(timestampNanoseconds: time, direction: .input, endpointUniqueID: 11, endpointName: "Test Input", rawBytes: message.canonicalBytes, message: message)
}

func run() throws {
    let running = MIDIStreamDecoder().feed([0x90, 60, 100, 61, 0])
    try check(running.map(\.message) == [.noteOn(channel: 0, note: 60, velocity: 100), .noteOff(channel: 0, note: 61, velocity: 0)], "parser running status and zero velocity")
    try check(running[1].rawBytes == [61, 0], "running status preserves transmitted bytes")

    let fragmented = MIDIStreamDecoder()
    try check(fragmented.feed([0xF0, 0x7E, 0x7F]).isEmpty, "fragmented SysEx waits for terminator")
    let completed = fragmented.feed([0xF8, 0x06, 0x01, 0xF7])
    try check(completed.map(\.message) == [.realtime(0xF8), .systemExclusive([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7])], "realtime interleaves inside SysEx")
    try check(MIDIStreamDecoder().feed([0xC2, 10, 11]).count == 2, "one-byte running status")

    let profile = try InstrumentProfile.bundledPA700()
    try check(profile.firmware == "1.5.0", "bundled profile schema and firmware")
    let invalidProfile = InstrumentProfile(schemaVersion: 1, id: "bad", manufacturer: "Test", model: "Test", firmware: "1", identitySignatures: profile.identitySignatures, aliases: [:], requiredConfiguration: [], channels: ["right1": 17], mappings: [:], presets: [])
    do { try invalidProfile.validate(); throw HarnessFailure(description: "invalid profile accepted") }
    catch ArrangerLabError.invalidProfile { passed += 1; print("PASS  invalid profile rejected") }
    let driver = PA700Driver(profile: profile)
    let styleCatalog = try ArrangerStyleCatalog.bundledPA700()
    try check(styleCatalog.styles.filter { $0.category != "User" }.count == 379, "official PA700 factory Style catalog has 379 unique entries")
    try check(Set(styleCatalog.styles.map(\.address)).count == styleCatalog.styles.count, "factory and verified User Style MIDI addresses are unique")
    try check(styleCatalog.styles.contains(where: { $0.displayName == "Pop Hit" && $0.address == "0.0.21" }), "category-prefixed Style names are preserved")
    try check(styleCatalog.styles.contains(where: { $0.displayName == "Dance Pop Reload" && $0.address == "0.3.6" }), "multiword category-prefixed Style names are preserved")
    guard let brushBallad = styleCatalog.styles.first(where: { $0.displayName == "Brush Ballad" }) else {
        throw HarnessFailure(description: "Brush Ballad missing")
    }
    try check(brushBallad.address == "0.1.4", "Brush Ballad official address is 0.1.4")
    let brushBalladSelection = try driver.compile(.selectArrangerStyle(styleID: brushBallad.id), allowDraft: false)
    try check(brushBalladSelection.map(\.message) == [
        .controlChange(channel: 15, controller: 0, value: 0),
        .controlChange(channel: 15, controller: 32, value: 1),
        .programChange(channel: 15, program: 4)
    ], "Verified Style selection compiles exact Control-channel bank/program sequence operationally")
    try check(profile.mappings["styleSelection"]?.status == .verified, "Style selection profile mapping is Verified")
    guard let jpdStyle = styleCatalog.styles.first(where: { $0.id == "user-style-jpd" }) else {
        throw HarnessFailure(description: "verified User Style JPD missing")
    }
    try check(jpdStyle.address == "2.10.0", "User Style JPD preserves the documented and physically verified address 2.10.0")
    try check(jpdStyle.libraryName == "User" && jpdStyle.userBankName == "JPD", "User Style JPD resolves through User bank JPD")
    try check(ArrangerStyle.userBankNames.count == 12
        && ArrangerStyle.userBankNames[6] == "PW"
        && ArrangerStyle.userBankNames[11] == "User 12", "PA700 User Style hierarchy preserves all 12 photographed bank labels")
    let jpdSelection = try driver.compile(.selectArrangerStyle(styleID: jpdStyle.id), allowDraft: false)
    try check(jpdSelection.map(\.message) == [
        .controlChange(channel: 15, controller: 0, value: 2),
        .controlChange(channel: 15, controller: 32, value: 10),
        .programChange(channel: 15, program: 0)
    ], "Verified User Style JPD compiles exact Control-channel bytes")
    let keyboardSetLibrary = try KeyboardSetLibraryCatalog.bundledPA700()
    try check(keyboardSetLibrary.keyboardSets.count == 298, "official PA700 Keyboard Set Library has 298 unique factory entries")
    try check(Set(keyboardSetLibrary.keyboardSets.map(\.address)).count == 298, "factory Keyboard Set Library MIDI addresses are unique")
    guard let concertGrandSet = keyboardSetLibrary.keyboardSets.first(where: { $0.displayName == "Concert Grand" }),
          let jimmyOrganSet = keyboardSetLibrary.keyboardSets.first(where: { $0.displayName == "Jimmy Organ" }) else {
        throw HarnessFailure(description: "known Keyboard Set Library entries missing")
    }
    try check(concertGrandSet.address == "16.0.0", "Concert Grand Keyboard Set official address is 16.0.0")
    try check(jimmyOrganSet.address == "16.1.0", "Jimmy Organ Keyboard Set official address is 16.1.0")
    let concertGrandSetSelection = try driver.compile(.selectKeyboardSetLibraryEntry(entryID: concertGrandSet.id), allowDraft: false)
    try check(concertGrandSetSelection.map(\.message) == [
        .controlChange(channel: 15, controller: 0, value: 16),
        .controlChange(channel: 15, controller: 32, value: 0),
        .programChange(channel: 15, program: 0)
    ], "Verified Keyboard Set Library selection compiles exact Control-channel bank/program sequence operationally")
    let jimmyOrganSetSelection = try driver.compile(.selectKeyboardSetLibraryEntry(entryID: jimmyOrganSet.id), allowDraft: false)
    try check(jimmyOrganSetSelection.map(\.message) == [
        .controlChange(channel: 15, controller: 0, value: 16),
        .controlChange(channel: 15, controller: 32, value: 1),
        .programChange(channel: 15, program: 0)
    ], "Physically confirmed Jimmy Organ Keyboard Set compiles as 16.1.0 operationally")
    try check(profile.mappings["keyboardSetLibrarySelection"]?.status == .verified, "Keyboard Set Library profile mapping is Verified")
    let musicalIntent = MusicalIntentTranslator.translate(
        "Jimmy Organ com Brush Ballad na variação 3",
        keyboardSets: keyboardSetLibrary.keyboardSets,
        styles: styleCatalog.styles
    )
    try check(musicalIntent.keyboardSet?.id == jimmyOrganSet.id, "musical intent resolves exact Keyboard Set name")
    try check(musicalIntent.style?.id == brushBallad.id, "musical intent resolves exact Style name")
    try check(musicalIntent.variation == 3, "musical intent resolves accented Portuguese variation")
    let partialIntent = MusicalIntentTranslator.translate(
        "Use Brush Ballad, var 2",
        keyboardSets: keyboardSetLibrary.keyboardSets,
        styles: styleCatalog.styles
    )
    try check(partialIntent.keyboardSet == nil && partialIntent.style?.id == brushBallad.id && partialIntent.variation == 2, "musical intent preserves unspecified fields")
    let wordVariationIntent = MusicalIntentTranslator.translate(
        "Concert Grand na variação três agora",
        keyboardSets: keyboardSetLibrary.keyboardSets,
        styles: styleCatalog.styles
    )
    try check(wordVariationIntent.keyboardSet?.id == concertGrandSet.id && wordVariationIntent.variation == 3, "musical intent accepts variation written as a word")
    let unknownIntent = MusicalIntentTranslator.translate(
        "Quero um som espacial e aveludado",
        keyboardSets: keyboardSetLibrary.keyboardSets,
        styles: styleCatalog.styles
    )
    try check(unknownIntent.isEmpty, "musical intent refuses unsupported semantic guesses")
    let target = try KeyboardPartTarget(zone: .right, layer: 1)
    let sceneDate = Date(timeIntervalSince1970: 123)
    let scene = PerformanceScene(
        name: "Restaurante",
        keyboardSetEntryID: jimmyOrganSet.id,
        styleID: brushBallad.id,
        variation: 3,
        parts: [
            .init(target: target, presetID: "jimmy-organ", volume: 0.5, expression: 0.75, pan: -0.25)
        ],
        createdAt: sceneDate,
        updatedAt: sceneDate
    )
    let sceneActions = try scene.actions()
    try check(sceneActions.count == 7, "performance scene compiles every declared action")
    try check(sceneActions[0] == .selectArrangerStyle(styleID: brushBallad.id), "performance scene applies Style first")
    try check(sceneActions[1] == .selectKeyboardSetLibraryEntry(entryID: jimmyOrganSet.id), "performance scene applies Keyboard Set after Style")
    try check(sceneActions[2] == .selectArrangerElement(.variation3), "performance scene applies exact Variation")
    try check(sceneActions[3] == .selectDevicePreset(target: target, presetID: "jimmy-organ"), "performance scene applies exact verified part preset")
    let sceneURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-scenes.json")
    defer { try? FileManager.default.removeItem(at: sceneURL) }
    try PerformanceSceneStore.save([scene], to: sceneURL)
    let loadedScenes = try PerformanceSceneStore.load(from: sceneURL)
    try check(loadedScenes == [scene], "performance scene JSON round trip")
    var invalidScene = scene
    invalidScene.variation = 5
    do { try invalidScene.validate(); throw HarnessFailure(description: "invalid scene variation accepted") }
    catch ArrangerLabError.invalidValue { passed += 1; print("PASS  invalid scene variation rejected") }
    let firstSetListItem = PerformanceSetListItem(sceneID: scene.id)
    let repeatedSetListItem = PerformanceSetListItem(sceneID: scene.id)
    let setList = PerformanceSetList(
        name: "Casamento",
        items: [firstSetListItem, repeatedSetListItem],
        createdAt: sceneDate,
        updatedAt: sceneDate
    )
    try setList.validate()
    try check(setList.items.map(\.sceneID) == [scene.id, scene.id], "set list supports repeating a scene in the running order")
    let setListURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-setlists.json")
    defer { try? FileManager.default.removeItem(at: setListURL) }
    try PerformanceSetListStore.save([setList], to: setListURL)
    let loadedSetLists = try PerformanceSetListStore.load(from: setListURL)
    try check(loadedSetLists == [setList], "performance set list JSON round trip")
    var invalidSetList = setList
    invalidSetList.items.append(firstSetListItem)
    do { try invalidSetList.validate(); throw HarnessFailure(description: "duplicate set list item ID accepted") }
    catch ArrangerLabError.invalidValue { passed += 1; print("PASS  duplicate set list item ID rejected") }
    let showPreset = ShowPreset(
        songTitle: "Abertura",
        songBookNumber: 4_273,
        transposeSemitones: -2,
        parts: [
            .init(
                part: .upper1,
                displayName: "Shape of you",
                soundID: "ch1-121-64-1",
                soundLibrary: "User"
            ),
            .init(part: .upper2, displayName: "Strings"),
            .init(part: .upper3, displayName: "Desligado", isEnabled: false),
            .init(part: .lower, displayName: "Acoustic Bass")
        ],
        effectsSummary: "Reverb curto",
        notes: "Entrada após a contagem",
        originalKey: "G",
        source: .init(
            catalogID: "teste",
            catalogSongID: "abertura",
            documentName: "show.pdf",
            startPage: 2,
            endPage: 3,
            sourceURL: "https://example.com/repertorio"
        ),
        chartLines: [
            .init(kind: .section, text: "[Refrão]"),
            .init(kind: .chords, text: "G D Em C"),
            .init(kind: .lyrics, text: "Linha de teste")
        ],
        readerSettings: .init(showChords: true, fontScale: 1.15),
        chartAnnotations: [
            .init(text: "Entrar depois da contagem", normalizedX: 0.74, normalizedY: 0.20)
        ],
        confirmedAt: sceneDate,
        createdAt: sceneDate,
        updatedAt: sceneDate
    )
    try showPreset.validate()
    try check(showPreset.isConfirmed, "show preset exposes physical confirmation readiness")
    let showPresetURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-show-presets.json")
    defer { try? FileManager.default.removeItem(at: showPresetURL) }
    try ShowPresetStore.save([showPreset], to: showPresetURL)
    let loadedShowPresets = try ShowPresetStore.load(from: showPresetURL)
    try check(loadedShowPresets == [showPreset], "show preset schema v2 JSON round trip includes chart and source")
    try check(
        loadedShowPresets[0].chartAnnotations.first?.text == "Entrar depois da contagem",
        "show preset preserves chart overlay annotations"
    )
    try check(loadedShowPresets[0].source?.sourceURL == "https://example.com/repertorio", "show preset preserves optional web source metadata")
    try check(
        loadedShowPresets[0].parts[0].soundID == "ch1-121-64-1"
            && loadedShowPresets[0].parts[0].soundLibrary == "User",
        "show preset preserves selected User sound catalogue reference"
    )
    var invalidShowPreset = showPreset
    invalidShowPreset.songBookNumber = 10_000
    do { try invalidShowPreset.validate(); throw HarnessFailure(description: "out-of-range show SongBook number accepted") }
    catch ArrangerLabError.invalidValue { passed += 1; print("PASS  show preset rejects SongBook outside 0...9999") }
    invalidShowPreset = showPreset
    invalidShowPreset.transposeSemitones = 13
    do { try invalidShowPreset.validate(); throw HarnessFailure(description: "out-of-range show transpose accepted") }
    catch ArrangerLabError.invalidValue { passed += 1; print("PASS  show preset rejects transpose outside -12...12") }
    invalidShowPreset = showPreset
    invalidShowPreset.chartAnnotations[0].normalizedX = 1.1
    do { try invalidShowPreset.validate(); throw HarnessFailure(description: "out-of-range chart annotation accepted") }
    catch ArrangerLabError.invalidValue { passed += 1; print("PASS  show preset rejects annotation outside normalized canvas") }
    invalidShowPreset = showPreset
    invalidShowPreset.parts.removeLast()
    do { try invalidShowPreset.validate(); throw HarnessFailure(description: "show preset accepted missing Lower part") }
    catch ArrangerLabError.invalidValue { passed += 1; print("PASS  show preset requires four exact keyboard parts") }
    var importedDraft = showPreset
    importedDraft.songBookNumber = nil
    importedDraft.confirmedAt = nil
    try importedDraft.validate()
    try check(!importedDraft.isConfirmed, "show preset accepts an imported draft without SongBook number")
    importedDraft.confirmedAt = sceneDate
    do { try importedDraft.validate(); throw HarnessFailure(description: "confirmed preset accepted without SongBook number") }
    catch ArrangerLabError.invalidValue { passed += 1; print("PASS  confirmed show preset requires a SongBook number") }

    let chartSource = "# [Refrão]\n> G D Em C\nLinha de teste\n"
    let parsedChart = ShowChartLine.parseEditorText(chartSource)
    try check(parsedChart.map(\.kind) == [.section, .chords, .lyrics, .space], "show chart editor parses section, chords, lyrics and space")
    try check(ShowChartLine.editorText(from: parsedChart) == chartSource, "show chart editor text round trip")
    let reparsedChart = ShowChartLine.parseEditorText(chartSource)
    try check(
        ShowChartLine.hasSameEditorContent(parsedChart, reparsedChart),
        "show chart dirty comparison ignores regenerated line IDs"
    )
    var changedChart = reparsedChart
    changedChart[1].text = "G D Em"
    try check(
        !ShowChartLine.hasSameEditorContent(parsedChart, changedChart),
        "show chart dirty comparison detects edited content"
    )
    let chartWithImportArtifacts: [ShowChartLine] = [
        .init(kind: .space, text: ""),
        .init(kind: .section, text: "[Dedilhado]"),
        .init(kind: .lyrics, text: "Parte 1 de 2"),
        .init(kind: .space, text: ""),
        .init(kind: .lyrics, text: "Parte 2 de 2"),
        .init(kind: .space, text: ""),
        .init(kind: .lyrics, text: "Parte de mim"),
        .init(kind: .space, text: "")
    ]
    let cleanedChart = ShowChartLine.removingImportArtifacts(from: chartWithImportArtifacts)
    try check(
        cleanedChart.map(\.text) == ["[Dedilhado]", "", "Parte de mim"],
        "show chart cleanup removes import pagination without deleting real lyrics"
    )
    try check(ShowMusicTheory.transposedKey("G", by: 2) == "A", "show key calculator resolves the sounding major key")
    try check(ShowMusicTheory.transposedKey("F#m", by: -2) == "Em", "show key calculator preserves minor mode")
    try check(ShowMusicTheory.transposedKey("Bb", by: 2) == "C", "show key calculator preserves flat spelling preference")
    try check(
        ShowMusicTheory.transposeChordLine("C G/B Am F", by: 2) == "D A/C# Bm G",
        "show chord transposer updates roots and slash bass notes"
    )
    try check(ShowMusicTheory.isChordLine("D7(4/9) C7M A/C# F#m"), "show PDF parser recognizes extended chord lines")
    try check(!ShowMusicTheory.isChordLine("Em todo caso perde o medo"), "show PDF parser does not classify lyric text as chords")
    let transposedChart = ShowMusicTheory.transposeChart(parsedChart, by: 2)
    try check(
        transposedChart[1].text == "A E F#m D" && transposedChart[2].text == parsedChart[2].text,
        "show chart transposition changes chords without changing lyrics"
    )
    let importedPDFPreset = try ShowPDFTextParser.makePreset(
        pageTexts: [
            """
            Minha Música
            Tom: G
            Parte 1 de 2
            [Intro] G D Em C
            G D Em C
            Esta é a primeira linha
            """,
            """
            [Refrão]
            C G/B Am
            Esta é a segunda página
            """
        ],
        sourceFileName: "minha-musica.pdf",
        sourceFingerprint: "fingerprint-teste"
    )
    try check(
        importedPDFPreset.songTitle == "Minha Música"
            && importedPDFPreset.originalKey == "G"
            && importedPDFPreset.source?.documentName == "minha-musica.pdf"
            && importedPDFPreset.source?.endPage == 2,
        "disposable PDF import extracts title, key and page metadata"
    )
    try check(
        importedPDFPreset.chartLines.contains(where: { $0.kind == .chords && $0.text == "G D Em C" })
            && importedPDFPreset.chartLines.contains(where: { $0.kind == .lyrics && $0.text == "Esta é a primeira linha" })
            && importedPDFPreset.chartLines.allSatisfy { !$0.isImportPaginationArtifact },
        "disposable PDF import separates chords from lyrics"
    )

    let legacyShowPresetURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-legacy-show-presets.json")
    defer { try? FileManager.default.removeItem(at: legacyShowPresetURL) }
    let legacyShowPresetJSON = """
    {
      "schemaVersion": 1,
      "presets": [{
        "id": "00000000-0000-4000-8000-000000000001",
        "songTitle": "Preset legado",
        "songBookNumber": 77,
        "transposeSemitones": 0,
        "parts": [
          {"part":"Upper 1","displayName":"Piano","isEnabled":true},
          {"part":"Upper 2","displayName":"Desligado","isEnabled":false},
          {"part":"Upper 3","displayName":"Desligado","isEnabled":false},
          {"part":"Lower","displayName":"Desligado","isEnabled":false}
        ],
        "effectsSummary": "",
        "notes": "",
        "createdAt": "2026-01-01T00:00:00Z",
        "updatedAt": "2026-01-01T00:00:00Z"
      }]
    }
    """
    try Data(legacyShowPresetJSON.utf8).write(to: legacyShowPresetURL, options: .atomic)
    let migratedLegacyPresets = try ShowPresetStore.load(from: legacyShowPresetURL)
    try check(
        migratedLegacyPresets.count == 1
            && migratedLegacyPresets[0].songBookNumber == 77
            && migratedLegacyPresets[0].chartLines.isEmpty
            && migratedLegacyPresets[0].chartAnnotations.isEmpty
            && migratedLegacyPresets[0].source == nil,
        "show preset schema v1 loads with schema v2 defaults"
    )

    let botecoCatalog = try BundledShowCatalog.botecoJul3()
    try check(botecoCatalog.entries.count == 57, "Boteco Jul3 catalog contains exactly 57 songs")
    try check(
        botecoCatalog.entries.first?.songTitle == "Querendo Te Amar"
            && botecoCatalog.entries.last?.songTitle == "Flor",
        "Boteco Jul3 catalog preserves PDF running order"
    )
    let multiPageSongs = botecoCatalog.entries.filter { $0.startPage != $0.endPage }
    try check(
        multiPageSongs.map(\.songTitle) == ["Convite de Casamento", "Evidências", "Sinônimos"]
            && multiPageSongs.map { $0.endPage - $0.startPage } == [1, 1, 1],
        "Boteco Jul3 catalog preserves the three two-page songs"
    )
    try check(
        botecoCatalog.entries.allSatisfy { !$0.originalKey.isEmpty && !$0.chartLines.isEmpty },
        "Boteco Jul3 catalog has a key and editable chart for every song"
    )
    let firstCatalogMerge = botecoCatalog.merging(presets: [], setLists: [], now: sceneDate)
    try check(
        firstCatalogMerge.presets.count == 57
            && firstCatalogMerge.importedCount == 57
            && firstCatalogMerge.setLists.count == 1
            && firstCatalogMerge.setLists[0].items.count == 57,
        "first Boteco import creates 57 drafts and the complete set list"
    )
    try check(firstCatalogMerge.presets.allSatisfy { !$0.isConfirmed && $0.songBookNumber == nil }, "Boteco import keeps all songs blocked as drafts")
    let repeatedCatalogMerge = botecoCatalog.merging(
        presets: firstCatalogMerge.presets,
        setLists: firstCatalogMerge.setLists,
        now: sceneDate.addingTimeInterval(60)
    )
    try check(
        repeatedCatalogMerge.presets == firstCatalogMerge.presets
            && repeatedCatalogMerge.setLists == firstCatalogMerge.setLists
            && repeatedCatalogMerge.importedCount == 0,
        "Boteco reimport is idempotent"
    )
    var editedCatalogPresets = firstCatalogMerge.presets
    editedCatalogPresets[0].songBookNumber = 123
    editedCatalogPresets[0].notes = "Entrada depois da fala"
    editedCatalogPresets[0].chartLines[0].text = "Edição do músico"
    let preservedCatalogMerge = botecoCatalog.merging(
        presets: editedCatalogPresets,
        setLists: firstCatalogMerge.setLists,
        now: sceneDate.addingTimeInterval(120)
    )
    try check(preservedCatalogMerge.presets[0] == editedCatalogPresets[0], "Boteco reimport preserves preset configuration and chart edits")
    var incompleteCatalogSetLists = firstCatalogMerge.setLists
    incompleteCatalogSetLists[0].items.removeFirst()
    let restoredCatalogSetListMerge = botecoCatalog.merging(
        presets: firstCatalogMerge.presets,
        setLists: incompleteCatalogSetLists,
        now: sceneDate.addingTimeInterval(180)
    )
    try check(restoredCatalogSetListMerge.setLists[0].items.count == 57, "manual Boteco reimport restores a missing set-list song")

    let showboatCatalog = try BundledShowCatalog.showboatJul23()
    try check(showboatCatalog.schemaVersion == 2, "Showboat catalog schema includes the Jul 23 preparation update")
    let expectedShowboatTitles = [
        "Pra Sempre Com Você", "Chora, Me Liga", "Pode Chorar", "Propaganda",
        "Perdoou Nada (Part. Jorge & Mateus)", "Barulho do Foguete",
        "Ilusão de Ótica (part. Ana Castela)", "5 Regras", "Briga Feia",
        "Vidinha de Balada", "Gosta de Rua", "Mala dos Porta-Mala", "Sinais",
        "Você Não Sabe o Que É Amor", "Te Vivo", "Aí Já Era", "O Que É Que Tem?",
        "A Maior Saudade", "Água Com Açúcar", "Cuida Bem Dela", "Tubarões",
        "Homem de Família", "Nosso Santo Bateu", "Evidências", "Seu Astral",
        "Amo Noite e Dia"
    ]
    let expectedShowboatKeys = [
        "G#m", "C", "C", "D", "Cm", "G#m", "B", "C#m", "Bb", "D", "F#", "G", "C",
        "F#", "D", "Em", "G", "B", "Eb", "Am", "Ab", "E", "C", "E", "D", "C#m"
    ]
    try check(showboatCatalog.entries.count == 26, "Showboat Jul 23 catalog contains exactly 26 songs")
    try check(showboatCatalog.entries.map(\.songTitle) == expectedShowboatTitles, "Showboat catalog preserves the goJam running order")
    try check(showboatCatalog.entries.map(\.originalKey) == expectedShowboatKeys, "Showboat catalog preserves every goJam key")
    try check(
        showboatCatalog.sourceURL == "https://gojam.fm/caio-e-matheus/setlists/showboat-jul-23"
            && showboatCatalog.entries.allSatisfy { $0.artist?.isEmpty == false },
        "Showboat catalog preserves web provenance and artist metadata"
    )
    try check(
        showboatCatalog.entries.allSatisfy { entry in
            entry.chartLines.contains(where: { $0.kind == .lyrics })
                && entry.chartLines.contains(where: { $0.kind == .chords })
                && entry.chartLines.allSatisfy { !$0.text.contains("|") }
        },
        "Showboat catalog has optimized editable lyrics and chords without guitar-tab rows"
    )
    guard let teVivoCatalogEntry = showboatCatalog.entries.first(where: { $0.songTitle == "Te Vivo" }) else {
        throw HarnessFailure(description: "Te Vivo catalog entry missing")
    }
    let cleanedTeVivoPreset = showboatCatalog.preset(for: teVivoCatalogEntry, now: sceneDate)
    try check(
        cleanedTeVivoPreset.chartLines.allSatisfy { !$0.isImportPaginationArtifact },
        "Showboat preset import removes pagination artifacts from the performance chart"
    )
    let combinedCatalogMerge = showboatCatalog.merging(
        presets: firstCatalogMerge.presets,
        setLists: firstCatalogMerge.setLists,
        now: sceneDate.addingTimeInterval(240)
    )
    try check(
        combinedCatalogMerge.presets.count == 83
            && combinedCatalogMerge.importedCount == 26
            && combinedCatalogMerge.setLists.count == 2
            && combinedCatalogMerge.setLists.first(where: { $0.sourceCatalogID == showboatCatalog.catalogID })?.items.count == 26,
        "Showboat import creates 26 independent drafts and its complete set list"
    )
    var editedShowboatPresets = combinedCatalogMerge.presets
    guard let firstShowboatIndex = editedShowboatPresets.firstIndex(where: {
        $0.source?.catalogID == showboatCatalog.catalogID
    }) else {
        throw HarnessFailure(description: "Showboat preset missing after import")
    }
    editedShowboatPresets[firstShowboatIndex].originalKey = "Am"
    editedShowboatPresets[firstShowboatIndex].transposeSemitones = -2
    editedShowboatPresets[firstShowboatIndex].chartLines[0].text = "Edição local"
    let repeatedShowboatMerge = showboatCatalog.merging(
        presets: editedShowboatPresets,
        setLists: combinedCatalogMerge.setLists,
        now: sceneDate.addingTimeInterval(300)
    )
    try check(
        repeatedShowboatMerge.presets[firstShowboatIndex] == editedShowboatPresets[firstShowboatIndex]
            && repeatedShowboatMerge.importedCount == 0,
        "Showboat reimport preserves tone, transpose and chart edits"
    )

    let pianoBlockPlan = try BundledShowBlockPlan.showboatJul23PianoBlockA()
    let preparedShowboat = pianoBlockPlan.merging(
        presets: combinedCatalogMerge.presets,
        setLists: combinedCatalogMerge.setLists,
        applyOperationalDefaults: true,
        now: sceneDate.addingTimeInterval(360)
    )
    guard let pianoBlock = preparedShowboat.setLists.first(where: {
        $0.sourceCatalogID == pianoBlockPlan.blockID
    }) else {
        throw HarnessFailure(description: "Showboat Piano Block A set list missing")
    }
    let pianoBlockPresets = pianoBlock.items.compactMap { item in
        preparedShowboat.presets.first(where: { $0.id == item.presetID })
    }
    let expectedPianoBlockTitles = [
        "Te Vivo", "Aí Já Era", "Pra Deixar Acontecer", "A Maior Saudade", "Água Com Açúcar",
        "Cuida Bem Dela", "Tubarões", "Homem de Família", "Medida Certa", "Evidências"
    ]
    let expectedPianoBlockKeys = ["D", "G", "G", "Am", "C", "C", "G", "C", "C", "C"]
    let expectedPianoBlockTranspose = [-3, -2, 0, 4, 1, 0, 0, 1, 1, 0]
    let expectedPianoBlockSounds = [
        "Piano", "Piano", "Piano", "Rhodes", "Rhodes",
        "Piano", "Piano", "Piano", "Piano", "Piano"
    ]
    try check(
        pianoBlockPresets.map(\.songTitle) == expectedPianoBlockTitles
            && pianoBlockPresets.map(\.originalKey) == expectedPianoBlockKeys
            && pianoBlockPresets.map(\.transposeSemitones) == expectedPianoBlockTranspose,
        "Showboat Piano Block A preserves the requested running order, keys and transpose values"
    )
    try check(
        pianoBlockPresets.map { $0.parts.first(where: { $0.part == .upper1 })?.displayName ?? "" }
            == expectedPianoBlockSounds
            && pianoBlockPresets.allSatisfy {
                $0.parts.first(where: { $0.part == .upper1 })?.soundLibrary == "USER · JPD"
                    && $0.parts.filter { $0.part != .upper1 }.allSatisfy { !$0.isEnabled }
            },
        "Showboat Piano Block A references USER JPD on Upper 1"
    )
    try check(
        pianoBlockPresets.allSatisfy { $0.arrangerStyleID == "user-style-jpd" && $0.isReadyToPlay }
            && pianoBlockPresets.map(\.keyboardSetSlot) == [1, 1, 1, 2, 2, 1, 1, 1, 1, 1],
        "Showboat Piano Block A has one-click JPD Piano and Rhodes setups"
    )
    var locallyEditedBlock = preparedShowboat.presets
    guard let teVivoIndex = locallyEditedBlock.firstIndex(where: { $0.songTitle == "Te Vivo" }) else {
        throw HarnessFailure(description: "Te Vivo preset missing from Piano Block A")
    }
    locallyEditedBlock[teVivoIndex].transposeSemitones = -1
    let nonDestructiveBlockMerge = pianoBlockPlan.merging(
        presets: locallyEditedBlock,
        setLists: preparedShowboat.setLists,
        applyOperationalDefaults: false,
        now: sceneDate.addingTimeInterval(420)
    )
    try check(
        nonDestructiveBlockMerge.presets[teVivoIndex].transposeSemitones == -1
            && nonDestructiveBlockMerge.importedCount == 0,
        "Piano Block reimport preserves later local edits after the one-time preparation"
    )
    let showSetList = ShowSetList(
        name: "Sexta-feira",
        items: [.init(presetID: showPreset.id), .init(presetID: showPreset.id)],
        createdAt: sceneDate,
        updatedAt: sceneDate
    )
    try showSetList.validate()
    try check(showSetList.items.map(\.presetID) == [showPreset.id, showPreset.id], "show set list supports repeating a preset")
    let showSetListURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-show-setlists.json")
    defer { try? FileManager.default.removeItem(at: showSetListURL) }
    try ShowSetListStore.save([showSetList], to: showSetListURL)
    let loadedShowSetLists = try ShowSetListStore.load(from: showSetListURL)
    try check(loadedShowSetLists == [showSetList], "show set list JSON round trip")
    let legacyShowSetListURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-legacy-show-setlists.json")
    defer { try? FileManager.default.removeItem(at: legacyShowSetListURL) }
    let legacyShowSetListJSON = """
    {
      "schemaVersion": 1,
      "setLists": [{
        "id": "00000000-0000-4000-8000-000000000011",
        "name": "Repertório legado",
        "items": [{
          "id": "00000000-0000-4000-8000-000000000012",
          "presetID": "00000000-0000-4000-8000-000000000001"
        }],
        "createdAt": "2026-01-01T00:00:00Z",
        "updatedAt": "2026-01-01T00:00:00Z"
      }]
    }
    """
    try Data(legacyShowSetListJSON.utf8).write(to: legacyShowSetListURL, options: .atomic)
    let migratedLegacySetLists = try ShowSetListStore.load(from: legacyShowSetListURL)
    try check(
        migratedLegacySetLists.count == 1 && migratedLegacySetLists[0].sourceCatalogID == nil,
        "show set list schema v1 loads with schema v2 defaults"
    )
    var changedOperationalReference = showPreset
    changedOperationalReference.songBookNumber = 4_274
    try check(!changedOperationalReference.hasSameOperationalReference(as: showPreset), "show preset detects operational changes that require reconfirmation")
    var changedChartOnly = showPreset
    changedChartOnly.chartLines[2].text = "Letra corrigida"
    try check(changedChartOnly.hasSameOperationalReference(as: showPreset), "chart edits do not require PA700 reconfirmation")
    let showSelection = try driver.compile(.selectSongBookEntry(number: showPreset.songBookNumber!), allowDraft: false)
    try check(showSelection.map(\.message) == [
        .controlChange(channel: 15, controller: 99, value: 2),
        .controlChange(channel: 15, controller: 98, value: 64),
        .controlChange(channel: 15, controller: 6, value: 42),
        .controlChange(channel: 15, controller: 38, value: 73)
    ], "show preset applies only the verified SongBook selection sequence")
    let volume = try driver.compile(.setPartVolume(target: target, level: 0.5), allowDraft: false)
    try check(volume.first?.message == .controlChange(channel: 0, controller: 7, value: 64), "Verified normalized volume compiles operationally")
    let expression = try driver.compile(.setPartExpression(target: target, level: 0.5), allowDraft: false)
    try check(expression.first?.message == .controlChange(channel: 0, controller: 11, value: 64), "Verified normalized expression compiles operationally")
    try check(profile.mappings["partExpression"]?.status == .verified, "partExpression profile mapping is Verified")
    try check(driver.interpret(.controlChange(channel: 0, controller: 11, value: 64)) == [.setPartExpression(target: target, level: Double(64) / 127)], "CC11 ch1 interprets as right/layer 1 expression")
    let panCenter = try driver.compile(.setPartPan(target: target, position: 0), allowDraft: false)
    try check(panCenter.first?.message == .controlChange(channel: 0, controller: 10, value: 64), "Verified normalized pan compiles center operationally")
    try check(profile.mappings["partPan"]?.status == .verified, "partPan profile mapping is Verified")
    try check(driver.interpret(.controlChange(channel: 0, controller: 10, value: 0)) == [.setPartPan(target: target, position: -1)], "CC10 ch1 interprets far left")
    try check(driver.interpret(.controlChange(channel: 0, controller: 10, value: 64)) == [.setPartPan(target: target, position: 0)], "CC10 ch1 interprets center")
    try check(driver.interpret(.controlChange(channel: 0, controller: 10, value: 127)) == [.setPartPan(target: target, position: 1)], "CC10 ch1 interprets far right")
    let damperOn = try driver.compile(.setPartDamper(target: target, engaged: true), allowDraft: false)
    try check(damperOn.first?.message == .controlChange(channel: 0, controller: 64, value: 127), "Verified Damper compiles CC64 ON operationally")
    let damperOff = try driver.compile(.setPartDamper(target: target, engaged: false), allowDraft: false)
    try check(damperOff.first?.message == .controlChange(channel: 0, controller: 64, value: 0), "Verified Damper compiles CC64 OFF operationally")
    try check(profile.mappings["partDamper"]?.status == .verified, "partDamper profile mapping is Verified")
    try check(driver.interpret(.controlChange(channel: 0, controller: 64, value: 63)) == [.setPartDamper(target: target, engaged: false)], "CC64 below threshold interprets Damper OFF")
    try check(driver.interpret(.controlChange(channel: 0, controller: 64, value: 64)) == [.setPartDamper(target: target, engaged: true)], "CC64 threshold interprets Damper ON")
    let classicPiano = try driver.compile(.selectDevicePreset(target: target, presetID: "classic-piano"), allowDraft: false)
    try check(classicPiano.map(\.message) == [
        .controlChange(channel: 0, controller: 0, value: 121),
        .controlChange(channel: 0, controller: 32, value: 4),
        .programChange(channel: 0, program: 0)
    ], "Verified Classic Piano compiles operationally")
    let jimmyOrgan = try driver.compile(.selectDevicePreset(target: target, presetID: "jimmy-organ"), allowDraft: false)
    try check(jimmyOrgan.map(\.message) == [
        .controlChange(channel: 0, controller: 0, value: 121),
        .controlChange(channel: 0, controller: 32, value: 13),
        .programChange(channel: 0, program: 18)
    ], "Verified Jimmy Organ compiles operationally")
    let grandPiano = try driver.compile(.selectDevicePreset(target: target, presetID: "grand-piano"), allowDraft: false)
    try check(grandPiano.map(\.message) == [
        .controlChange(channel: 0, controller: 0, value: 121),
        .controlChange(channel: 0, controller: 32, value: 3),
        .programChange(channel: 0, program: 0)
    ], "Verified Grand Piano compiles operationally")
    let arrangerStart = try driver.compile(.setTransport(domain: .arranger, state: .start), allowDraft: false)
    try check(arrangerStart.map(\.message) == [.realtime(0xFA)], "Verified arranger Start compiles operationally")
    let arrangerStop = try driver.compile(.setTransport(domain: .arranger, state: .stop), allowDraft: false)
    try check(arrangerStop.map(\.message) == [.realtime(0xFC)], "Verified arranger Stop compiles operationally")
    let verifiedSongBookSelection = try driver.compile(.selectSongBookEntry(number: 9_000), allowDraft: false)
    try check(verifiedSongBookSelection.map(\.message) == [.controlChange(channel: 15, controller: 99, value: 2), .controlChange(channel: 15, controller: 98, value: 64), .controlChange(channel: 15, controller: 6, value: 90), .controlChange(channel: 15, controller: 38, value: 0)], "Verified SongBook 9000 compiles operationally")
    let verifiedClockStart = try driver.compile(.setTransport(domain: .midiClock, state: .start), allowDraft: false)
    try check(verifiedClockStart.map(\.message) == [.realtime(0xFA)], "Verified MIDI Clock transport compiles Start operationally")
    let verifiedClockContinue = try driver.compile(.setTransport(domain: .midiClock, state: .continue), allowDraft: false)
    try check(verifiedClockContinue.map(\.message) == [.realtime(0xFB)], "Verified MIDI Clock transport compiles Continue operationally")
    let verifiedClockStop = try driver.compile(.setTransport(domain: .midiClock, state: .stop), allowDraft: false)
    try check(verifiedClockStop.map(\.message) == [.realtime(0xFC)], "Verified MIDI Clock transport compiles Stop operationally")
    for element in ArrangerElement.allCases {
        let compiled = try driver.compile(.selectArrangerElement(element), allowDraft: false)
        try check(compiled == [.init(message: .programChange(channel: 15, program: element.rawValue), mappingID: "arrangerElement.\(element.rawValue)")], "Verified PA700 \(element.displayName) uses Control-channel PC\(element.rawValue)")
    }
    let keyboardSet4 = try driver.compile(.selectKeyboardSet(slot: 4), allowDraft: true)
    try check(keyboardSet4 == [.init(message: .programChange(channel: 15, program: 67), mappingID: "keyboardSet")], "PA700 Keyboard Set 4 uses Control-channel PC67")
    let operationalKeyboardSet2 = try driver.compile(.selectKeyboardSet(slot: 2), allowDraft: false)
    try check(operationalKeyboardSet2 == [.init(message: .programChange(channel: 15, program: 65), mappingID: "keyboardSet")], "Verified Keyboard Set 2 compiles operationally")
    do { _ = try driver.compile(.selectKeyboardSet(slot: 5), allowDraft: true); throw HarnessFailure(description: "invalid Keyboard Set slot accepted") }
    catch ArrangerLabError.invalidValue { passed += 1; print("PASS  invalid Keyboard Set slot rejected") }
    let transposeMinus3 = try driver.compile(.setMasterTranspose(semitones: -3), allowDraft: false)
    try check(transposeMinus3.map(\.message) == [.systemExclusive([0xF0, 0x7F, 0x7F, 0x04, 0x04, 0x00, 0x3D, 0xF7])], "Verified master transpose -3 compiles exact SysEx")
    do { _ = try driver.compile(.setMasterTranspose(semitones: 13), allowDraft: false); throw HarnessFailure(description: "invalid master transpose accepted") }
    catch ArrangerLabError.invalidValue { passed += 1; print("PASS  invalid master transpose rejected") }
    try check(driver.interpret(.programChange(channel: 15, program: 91)) == [.selectArrangerElement(.break)], "Control-channel PC91 interprets as Break")
    for control in ArrangerControl.allCases {
        let compiled = try driver.compile(.triggerArrangerControl(control), allowDraft: false)
        try check(compiled == [.init(message: .programChange(channel: 15, program: control.rawValue), mappingID: "arrangerControl.\(control.rawValue)")], "Verified PA700 \(control.displayName) uses Control-channel PC\(control.rawValue)")
    }
    do { _ = try driver.compile(.setPartVolume(target: target, level: 1.1), allowDraft: true); throw HarnessFailure(description: "out-of-range value accepted") }
    catch ArrangerLabError.invalidValue { passed += 1; print("PASS  out-of-range normalized value rejected") }
    do { _ = try driver.compile(.setPartExpression(target: target, level: -0.1), allowDraft: true); throw HarnessFailure(description: "out-of-range expression accepted") }
    catch ArrangerLabError.invalidValue { passed += 1; print("PASS  out-of-range normalized expression rejected") }
    do { _ = try driver.compile(.setPartPan(target: target, position: 1.1), allowDraft: true); throw HarnessFailure(description: "out-of-range pan accepted") }
    catch ArrangerLabError.invalidValue { passed += 1; print("PASS  out-of-range normalized pan rejected") }

    let songBook = try driver.compile(.selectSongBookEntry(number: 4273), allowDraft: true)
    try check(songBook.map(\.message) == [.controlChange(channel: 15, controller: 99, value: 2), .controlChange(channel: 15, controller: 98, value: 64), .controlChange(channel: 15, controller: 6, value: 42), .controlChange(channel: 15, controller: 38, value: 73)], "SongBook NRPN encoding")
    let identity = MIDIMessage.systemExclusive([0xF0, 0x7E, 0x7F, 0x06, 0x02, 0x42, 0x60, 0x00, 0x5D, 0x00, 1, 5, 0, 0, 0xF7])
    try check(driver.identifies(identity), "PA700 universal identity match")

    let selectedPreset = MIDIProgramSelectionExtractor.lastComplete(in: [
        inputEvent(.controlChange(channel: 0, controller: 0, value: 121)),
        inputEvent(.controlChange(channel: 0, controller: 32, value: 4)),
        inputEvent(.programChange(channel: 0, program: 12))
    ], channel: 0)
    try check(selectedPreset == .init(channel: 0, bankMSB: 121, bankLSB: 4, program: 12), "exact preset extractor reads CC0.CC32.PC")

    let explicitJimmySelection = [
        inputEvent(.controlChange(channel: 0, controller: 0, value: 121)),
        inputEvent(.controlChange(channel: 0, controller: 32, value: 13)),
        inputEvent(.programChange(channel: 0, program: 18)),
        MIDIEvent(
            timestampNanoseconds: 2,
            direction: .input,
            endpointUniqueID: 11,
            endpointName: "Test Input",
            rawBytes: [0],
            message: .programChange(channel: 0, program: 0)
        )
    ]
    try check(
        MIDIProgramSelectionExtractor.lastComplete(in: explicitJimmySelection, channel: 0)
            == .init(channel: 0, bankMSB: 121, bankLSB: 13, program: 18),
        "preset extractor ignores status-less SysEx artifacts"
    )

    let batchStarted = Date(timeIntervalSince1970: 100)
    var batchCollector = BatchSoundCollector(catalog: .init(
        model: "PA700",
        firmware: "1.5.0",
        midiPreset: "ArrangerLab",
        startedAt: batchStarted,
        updatedAt: batchStarted
    ))
    try check(batchCollector.consume(inputEvent(.programChange(channel: 0, program: 0))) == nil, "batch mapping ignores incomplete program selection")
    _ = batchCollector.consume(inputEvent(.controlChange(channel: 1, controller: 0, value: 121)))
    _ = batchCollector.consume(inputEvent(.controlChange(channel: 1, controller: 32, value: 3)))
    try check(batchCollector.consume(inputEvent(.programChange(channel: 1, program: 0))) == nil, "batch mapping ignores channels other than Upper1")
    _ = batchCollector.consume(inputEvent(.controlChange(channel: 0, controller: 0, value: 121)))
    _ = batchCollector.consume(inputEvent(.controlChange(channel: 0, controller: 32, value: 3)))
    let mappedGrand = batchCollector.consume(inputEvent(.programChange(channel: 0, program: 0)), suggestedName: { _ in "Grand Piano" }, now: Date(timeIntervalSince1970: 101))
    try check(mappedGrand?.displayName == "Grand Piano" && batchCollector.catalog.entries.count == 1, "batch mapping captures canonical CC0.CC32.PC")
    _ = batchCollector.consume(inputEvent(.programChange(channel: 0, program: 0)), now: Date(timeIntervalSince1970: 102))
    try check(batchCollector.catalog.captureCount == 2 && batchCollector.catalog.entries[0].occurrenceCount == 2, "batch mapping deduplicates and counts repeated selections")
    let statuslessProgram = MIDIEvent(timestampNanoseconds: 3, direction: .input, endpointUniqueID: 11, endpointName: "Test Input", rawBytes: [1], message: .programChange(channel: 0, program: 1))
    try check(batchCollector.consume(statuslessProgram) == nil && batchCollector.catalog.entries.count == 1, "batch mapping ignores noncanonical artifacts")
    batchCollector.rename(id: batchCollector.catalog.entries[0].id, displayName: "Concert Grand", now: Date(timeIntervalSince1970: 103))
    try check(batchCollector.catalog.entries[0].displayName == "Concert Grand", "batch mapping supports later name review")
    let photoScreen = batchCollector.beginScreen(now: Date(timeIntervalSince1970: 104))
    _ = batchCollector.consume(inputEvent(.controlChange(channel: 0, controller: 32, value: 12)))
    _ = batchCollector.consume(inputEvent(.programChange(channel: 0, program: 0)), now: Date(timeIntervalSince1970: 105))
    _ = batchCollector.consume(inputEvent(.controlChange(channel: 0, controller: 32, value: 4)))
    _ = batchCollector.consume(inputEvent(.programChange(channel: 0, program: 0)), now: Date(timeIntervalSince1970: 106))
    try check(batchCollector.activeScreen?.entryIDs.count == 2, "photo screen preserves every captured address in order")
    _ = batchCollector.endScreen(now: Date(timeIntervalSince1970: 107))
    do {
        try batchCollector.assignNames(screenID: photoScreen.id, names: ["Pop Grand"])
        throw HarnessFailure(description: "photo screen accepted a shifted name list")
    } catch BatchSoundAssignmentError.countMismatch(expected: 2, received: 1) {
        passed += 1
        print("PASS  photo screen rejects mismatched name count atomically")
    }
    try batchCollector.assignNames(screenID: photoScreen.id, names: ["Pop Grand", "Classic Piano"], now: Date(timeIntervalSince1970: 108))
    let photoNames = batchCollector.catalog.screens[0].entryIDs.compactMap { id in
        batchCollector.catalog.entries.first(where: { $0.id == id })?.displayName
    }
    try check(photoNames == ["Pop Grand", "Classic Piano"], "photo screen assigns names in capture order")
    _ = batchCollector.beginScreen(now: Date(timeIntervalSince1970: 109))
    _ = batchCollector.consume(inputEvent(.controlChange(channel: 0, controller: 32, value: 13)))
    _ = batchCollector.consume(inputEvent(.programChange(channel: 0, program: 18)), now: Date(timeIntervalSince1970: 110))
    _ = batchCollector.undoLastScreenCapture(now: Date(timeIntervalSince1970: 111))
    try check(batchCollector.activeScreen?.entryIDs.isEmpty == true, "photo screen can undo an accidental last tap")
    _ = batchCollector.endScreen(now: Date(timeIntervalSince1970: 112))
    try check(batchCollector.catalog.screens.count == 1, "empty photo screens are discarded instead of consuming a page number")
    let batchURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-sounds.json")
    defer { try? FileManager.default.removeItem(at: batchURL) }
    try BatchSoundCatalogStore.save(batchCollector.catalog, to: batchURL)
    let loadedBatchCatalog = try BatchSoundCatalogStore.load(from: batchURL)
    try check(loadedBatchCatalog == batchCollector.catalog, "batch catalog JSON round trip")
    var legacyCatalogObject = try JSONSerialization.jsonObject(with: Data(contentsOf: batchURL)) as! [String: Any]
    legacyCatalogObject.removeValue(forKey: "screens")
    try JSONSerialization.data(withJSONObject: legacyCatalogObject).write(to: batchURL)
    let legacyBatchCatalog = try BatchSoundCatalogStore.load(from: batchURL)
    try check(legacyBatchCatalog.screens.isEmpty, "batch catalog loads pre-photo sessions without migration")
    let batchExport = BatchSoundCatalogStore.draftExport(from: batchCollector.catalog, generatedAt: Date(timeIntervalSince1970: 104))
    try check(batchExport.presets.allSatisfy { $0.status == .draft }, "batch export never promotes mappings to Verified")
    try check(batchExport.presets.first?.evidence.first?.bytes == [0xB0, 0, 121, 0xB0, 32, 3, 0xC0, 0], "batch export preserves exact raw selection bytes")

    var auditionCollector = BatchSoundCollector(catalog: batchCollector.catalog)
    let auditionID = auditionCollector.catalog.entries[0].id
    auditionCollector.setFavorite(id: auditionID, isFavorite: true, now: Date(timeIntervalSince1970: 113))
    auditionCollector.markAuditioned(id: auditionID, now: Date(timeIntervalSince1970: 114))
    auditionCollector.markVerified(id: auditionID, experimentPath: "/tmp/preset.arrlab", now: Date(timeIntervalSince1970: 115))
    try check(
        auditionCollector.catalog.entries[0].isFavorite
            && auditionCollector.catalog.entries[0].status == .verified
            && auditionCollector.catalog.entries[0].lastAuditionedAt == Date(timeIntervalSince1970: 115)
            && auditionCollector.catalog.entries[0].verificationExperimentPath == "/tmp/preset.arrlab"
            && auditionCollector.catalog.entries[0].verificationBasis == .individualAudition,
        "audition metadata promotes one catalog entry and preserves favorite state"
    )
    try BatchSoundCatalogStore.save(auditionCollector.catalog, to: batchURL)
    let reloadedAuditionCatalog = try BatchSoundCatalogStore.load(from: batchURL)
    try check(reloadedAuditionCatalog == auditionCollector.catalog, "audition metadata survives catalog JSON round trip")

    var preAuditionObject = try JSONSerialization.jsonObject(with: Data(contentsOf: batchURL)) as! [String: Any]
    var preAuditionEntries = preAuditionObject["entries"] as! [[String: Any]]
    for index in preAuditionEntries.indices {
        preAuditionEntries[index].removeValue(forKey: "isFavorite")
        preAuditionEntries[index].removeValue(forKey: "lastAuditionedAt")
        preAuditionEntries[index].removeValue(forKey: "verificationExperimentPath")
        preAuditionEntries[index].removeValue(forKey: "verificationBasis")
    }
    preAuditionObject["entries"] = preAuditionEntries
    try JSONSerialization.data(withJSONObject: preAuditionObject).write(to: batchURL)
    let preAuditionCatalog = try BatchSoundCatalogStore.load(from: batchURL)
    try check(
        preAuditionCatalog.entries.allSatisfy { !$0.isFavorite && $0.lastAuditionedAt == nil && $0.verificationExperimentPath == nil && $0.verificationBasis == nil },
        "catalog loads sessions created before audition metadata"
    )

    var sampledCollector = BatchSoundCollector(catalog: auditionCollector.catalog)
    let individuallyVerifiedID = sampledCollector.catalog.entries[0].id
    let promotedBySampling = sampledCollector.markAllVerifiedBySampling(
        experimentPath: "/tmp/catalog-sampling.arrlab",
        now: Date(timeIntervalSince1970: 116)
    )
    try check(
        promotedBySampling == sampledCollector.catalog.entries.count - 1
            && sampledCollector.catalog.entries.allSatisfy { $0.status == .verified }
            && sampledCollector.catalog.entries.first(where: { $0.id == individuallyVerifiedID })?.verificationBasis == .individualAudition
            && sampledCollector.catalog.entries.filter { $0.id != individuallyVerifiedID }.allSatisfy { $0.verificationBasis == .catalogSampling },
        "catalog sampling promotes remaining entries without weakening individual evidence"
    )

    let officialSounds = try PA700OfficialSoundCatalog.bundled()
    try check(officialSounds.sounds.count == 1_727, "official PA700 catalog contains all 1,727 sounds")
    try check(officialSounds.libraryCounts == ["Factory": 534, "Legacy": 505, "GM/XG": 688], "official PA700 catalog library totals")
    let officialAddresses = Set(officialSounds.sounds.map { "\($0.bankMSB).\($0.bankLSB).\($0.program)" })
    try check(officialAddresses.count == officialSounds.sounds.count, "official PA700 catalog addresses are unique")
    try check(officialSounds.userSlots.count == 512, "official PA700 catalog declares 512 User slots")
    let sixtyOrgan = MIDIProgramSelection(channel: 0, bankMSB: 121, bankLSB: 40, program: 16)
    let physicalCapture = BatchSoundEntry(selection: sixtyOrgan, displayName: "60's Organ", occurrenceCount: 2, source: .midiCapture)
    var mergeCollector = BatchSoundCollector(catalog: .init(
        model: "PA700",
        firmware: "1.5.0",
        midiPreset: "ArrangerLab",
        captureCount: 2,
        entries: [physicalCapture]
    ))
    let mergeSummary = mergeCollector.importOfficialSounds(officialSounds.sounds)
    let preservedPhysicalCapture = mergeCollector.catalog.entries.first(where: { $0.id == physicalCapture.id })
    try check(mergeCollector.catalog.entries.count == 1_727 && mergeCollector.catalog.captureCount == 2, "official import fills catalog without inventing captures")
    try check(mergeSummary.inserted == 1_726 && mergeSummary.enriched == 1 && mergeSummary.preservedCapturedNames == 1, "official import reports deterministic merge")
    try check(preservedPhysicalCapture?.displayName == "60's Organ" && preservedPhysicalCapture?.occurrenceCount == 2 && preservedPhysicalCapture?.library == "Factory", "official import preserves physical evidence and enriches metadata")
    try check(mergeCollector.catalog.entries.allSatisfy { $0.status == .draft }, "official import keeps every mapping Draft")
    let userOne = BatchSoundEntry(selection: .init(channel: 0, bankMSB: 121, bankLSB: 64, program: 0), displayName: "User One")
    let userTwo = BatchSoundEntry(selection: .init(channel: 0, bankMSB: 121, bankLSB: 64, program: 4), displayName: "User Two")
    let validationEntries = mergeCollector.catalog.entries + [userOne, userTwo]
    let fastPlan = BatchSoundFastValidationPlan.representatives(from: validationEntries)
    let bankCount = BatchSoundFastValidationPlan.bankCount(in: validationEntries)
    try check(bankCount == 91 && fastPlan.count == 92, "fast catalog validation selects one representative per bank plus every User sound")
    try check(Set(fastPlan.map(\.id)).count == fastPlan.count && fastPlan.contains(where: { $0.id == userOne.id }) && fastPlan.contains(where: { $0.id == userTwo.id }), "fast catalog validation is unique and includes all captured User sounds")
    try check(BatchSoundFastValidationPlan.capturedUserCount(in: validationEntries) == 2, "fast catalog validation counts captured User slots")

    let a = [event(.realtime(0xF8)), event(.noteOn(channel: 0, note: 60, velocity: 80)), event(.controlChange(channel: 0, controller: 7, value: 80))]
    let b = [event(.realtime(0xF8)), event(.noteOn(channel: 0, note: 61, velocity: 80)), event(.controlChange(channel: 0, controller: 7, value: 95))]
    let diff = CaptureDiffer.compare(a, b)
    try check(diff.count == 1 && diff[0].before == "80" && diff[0].after == "95", "diff ignores clock/notes and shows CC A to B")

    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("arrlab")
    defer { try? FileManager.default.removeItem(at: root) }
    let state = DeviceStateSnapshot(model: "PA700", firmware: "1.5.0", midiPreset: "ArrangerLab", clockSource: "Internal", mode: "Style Play", inputEndpoint: "In", outputEndpoint: "Out")
    let fixed = Date(timeIntervalSince1970: 0)
    let manifest = ArrLabManifest(schemaVersion: 1, experimentID: UUID(), title: "Test", createdAt: fixed, updatedAt: fixed, hypothesis: "CC7", mappingID: "partVolume", mappingStatus: .draft, deviceState: state, annotations: ["marker"])
    let experiment = ArrLabExperiment(manifest: manifest, events: [event(.controlChange(channel: 0, controller: 7, value: 95))], analysis: .init(notes: [], audioEvidence: [], manualConfirmations: [], spectralDistances: [:]))
    try ArrLabPackage.save(experiment, to: root)
    let loaded = try ArrLabPackage.load(from: root)
    try check(loaded == experiment, ".arrlab JSON/JSONL round trip")
    try Data("not json".utf8).write(to: root.appendingPathComponent("manifest.json"))
    do { _ = try ArrLabPackage.load(from: root); throw HarnessFailure(description: "corrupt package accepted") }
    catch ArrangerLabError.corruptCapture { passed += 1; print("PASS  corrupt .arrlab rejected") }
    try check(CaptureExporter.csv(events: b).hasPrefix("tick,status,data1,data2"), "AIArranger-compatible CSV export")
    try check(String(data: CaptureExporter.smf(events: b).prefix(4), encoding: .ascii) == "MThd", "SMF export")

    func tone(_ amplitude: Double, _ frequency: Double) -> AudioMetrics {
        let samples = (0..<4_800).map { Float(sin(2 * Double.pi * frequency * Double($0) / 48_000) * amplitude) }
        return AudioAnalyzer.analyze(samples: samples, sampleRate: 48_000)
    }
    let low = tone(0.1, 440), middle = tone(0.25, 440), high = tone(0.6, 440)
    try check(abs(middle.rms - 0.1768) < 0.01 && abs(middle.normalizedSpectrum.reduce(0, +) - 1) < 0.001, "synthetic audio RMS and normalized spectrum")
    try check(PA700EvidenceRules.volumePasses([low, middle, high]), "volume evidence monotonic and six dB rule")
    let expressionLow = tone(0.10, 440), expressionMiddle = tone(0.13, 440), expressionHigh = tone(0.18, 440)
    try check(PA700EvidenceRules.expressionPasses([expressionLow, expressionMiddle, expressionHigh]) && !PA700EvidenceRules.volumePasses([expressionLow, expressionMiddle, expressionHigh]), "expression evidence uses its distinct three dB rule")
    let expressionVerification = MappingEvidenceVerifier.partExpression(
        events: [
            event(.controlChange(channel: 0, controller: 11, value: 32)),
            event(.controlChange(channel: 0, controller: 11, value: 64)),
            event(.controlChange(channel: 0, controller: 11, value: 95))
        ],
        firmware: "1.5.0",
        expectedFirmware: "1.5.0",
        midiPreset: "ArrangerLab",
        identityConfirmed: true,
        audioPasses: true,
        manualConfirmations: [.init(prompt: "Expression right/layer 1 audibly changed", confirmed: true, note: "test")]
    )
    try check(expressionVerification.passed, "partExpression promotion requires CC11, audio and physical confirmation")
    let panVerification = MappingEvidenceVerifier.partPan(
        events: [
            event(.controlChange(channel: 0, controller: 10, value: 0)),
            event(.controlChange(channel: 0, controller: 10, value: 64)),
            event(.controlChange(channel: 0, controller: 10, value: 127))
        ],
        firmware: "1.5.0",
        expectedFirmware: "1.5.0",
        midiPreset: "ArrangerLab",
        identityConfirmed: true,
        audioCaptured: true,
        manualConfirmations: [.init(prompt: "Pan right/layer 1 moved left, center and right", confirmed: true, note: "test")]
    )
    try check(panVerification.passed, "partPan promotion requires CC10, audio and physical stereo confirmation")
    let damperVerification = MappingEvidenceVerifier.partDamper(
        events: [
            event(.controlChange(channel: 0, controller: 64, value: 0)),
            event(.controlChange(channel: 0, controller: 64, value: 127)),
            event(.controlChange(channel: 0, controller: 64, value: 0))
        ],
        firmware: "1.5.0",
        expectedFirmware: "1.5.0",
        midiPreset: "ArrangerLab",
        identityConfirmed: true,
        audibleComparisonCompleted: true,
        manualConfirmations: [.init(prompt: "Damper right/layer 1 sustained the second note and released on OFF", confirmed: true, note: "test")]
    )
    try check(damperVerification.passed, "partDamper promotion requires safe CC64 sequence and physical confirmation")
    try check(PA700EvidenceRules.presetABA(a1: middle, b: tone(0.25, 880), a2: middle), "preset A-B-A spectral rule")

    let verificationEvents = [
        event(.controlChange(channel: 0, controller: 7, value: 32)),
        event(.controlChange(channel: 0, controller: 7, value: 64)),
        event(.controlChange(channel: 0, controller: 7, value: 95))
    ]
    let confirmations = [ManualConfirmation(prompt: "Volume right/layer 1 audibly changed", confirmed: true, note: "heard")]
    let verifiedVolume = MappingEvidenceVerifier.partVolume(events: verificationEvents, firmware: "1.5.0", expectedFirmware: "1.5.0", midiPreset: "ArrangerLab", identityConfirmed: true, audioPasses: true, manualConfirmations: confirmations)
    try check(verifiedVolume.passed, "partVolume promotion requires complete evidence")
    let incompleteVolume = MappingEvidenceVerifier.partVolume(events: Array(verificationEvents.dropLast()), firmware: "1.5.0", expectedFirmware: "1.5.0", midiPreset: "ArrangerLab", identityConfirmed: true, audioPasses: true, manualConfirmations: confirmations)
    try check(!incompleteVolume.passed, "partVolume promotion rejects missing raw CC7")

    let arrangerConfirmations = [
        ManualConfirmation(prompt: "PA700 arranger started from external USB clock", confirmed: true, note: "heard"),
        ManualConfirmation(prompt: "PA700 arranger stopped from external USB clock", confirmed: true, note: "heard")
    ]
    let arrangerEvents = [event(.realtime(0xFA))]
        + Array(repeating: event(.realtime(0xF8)), count: 48)
        + [event(.realtime(0xFC))]
    let verifiedArranger = MappingEvidenceVerifier.arrangerTransport(events: arrangerEvents, firmware: "1.5.0", expectedFirmware: "1.5.0", midiPreset: "ArrangerLab", identityConfirmed: true, externalUSBConfirmed: true, internalRestored: true, audioDurationSeconds: 3, manualConfirmations: arrangerConfirmations)
    try check(verifiedArranger.passed, "arranger transport requires clock, Start/Stop, audio and physical confirmations")
    let unsafeArranger = MappingEvidenceVerifier.arrangerTransport(events: arrangerEvents, firmware: "1.5.0", expectedFirmware: "1.5.0", midiPreset: "ArrangerLab", identityConfirmed: true, externalUSBConfirmed: true, internalRestored: false, audioDurationSeconds: 3, manualConfirmations: arrangerConfirmations)
    try check(!unsafeArranger.passed, "arranger transport cannot verify before Internal clock is restored")

    let songBookEvents = [
        event(.controlChange(channel: 15, controller: 99, value: 2)),
        event(.controlChange(channel: 15, controller: 98, value: 64)),
        event(.controlChange(channel: 15, controller: 6, value: 90)),
        event(.controlChange(channel: 15, controller: 38, value: 0))
    ]
    let songBookConfirmations = [ManualConfirmation(prompt: "Displayed SongBook entry matched requested number 9000: ArrangerLab Test", confirmed: true, note: "displayed")]
    let verifiedSongBook = MappingEvidenceVerifier.songBook(events: songBookEvents, number: 9_000, expectedNumber: 9_000, displayedName: "ArrangerLab Test", expectedName: "ArrangerLab Test", firmware: "1.5.0", expectedFirmware: "1.5.0", midiPreset: "ArrangerLab", identityConfirmed: true, stylePlayConfirmed: true, manualConfirmations: songBookConfirmations)
    try check(verifiedSongBook.passed, "SongBook promotion requires exact channel-16 bytes and displayed entry")
    let wrongSongBook = MappingEvidenceVerifier.songBook(events: songBookEvents, number: 9_000, expectedNumber: 9_000, displayedName: "Wrong Entry", expectedName: "ArrangerLab Test", firmware: "1.5.0", expectedFirmware: "1.5.0", midiPreset: "ArrangerLab", identityConfirmed: true, stylePlayConfirmed: true, manualConfirmations: songBookConfirmations)
    try check(!wrongSongBook.passed, "SongBook promotion rejects the wrong displayed entry")

    var expert = ExpertSession()
    do { try expert.unlock(typedModel: "PA1000", connectedModel: "PA700"); throw HarnessFailure(description: "wrong Expert model accepted") }
    catch ArrangerLabError.invalidValue { passed += 1; print("PASS  Expert rejects wrong model") }
    try expert.unlock(typedModel: "pa700", connectedModel: "PA700")
    do { try expert.validateArbitrarySysEx(confirmed: false); throw HarnessFailure(description: "unconfirmed arbitrary SysEx accepted") }
    catch ArrangerLabError.invalidValue { passed += 1; print("PASS  arbitrary SysEx requires second confirmation") }
    expert.expire()
    try check(!expert.isUnlocked, "Expert expires")

    let semaphore = DispatchSemaphore(value: 0)
    var client = MIDIClientRef(), virtualDestination = MIDIEndpointRef()
    try check(MIDIClientCreateWithBlock("Arranger Lab Harness" as CFString, &client) { _ in } == noErr, "CoreMIDI test client")
    try check(MIDIDestinationCreateWithBlock(client, "Arranger Lab Virtual Destination" as CFString, &virtualDestination) { _, _ in semaphore.signal() } == noErr, "CoreMIDI virtual destination")
    defer { MIDIEndpointDispose(virtualDestination); MIDIClientDispose(client) }
    var uniqueID: Int32 = 0
    try check(MIDIObjectGetIntegerProperty(virtualDestination, kMIDIPropertyUniqueID, &uniqueID) == noErr, "virtual endpoint Unique ID")
    let transport = try MIDITransport()
    transport.refreshEndpoints()
    try transport.connect(sourceID: nil, destinationID: uniqueID)
    do { try transport.sendScheduled(Array(repeating: .init(message: .realtime(0xF8), mappingID: "load"), count: 4_097)); throw HarnessFailure(description: "oversized queue accepted") }
    catch ArrangerLabError.queueFull { passed += 1; print("PASS  full MIDI queue rejected") }
    try transport.send(.noteOn(channel: 0, note: 60, velocity: 80))
    try check(semaphore.wait(timeout: .now() + 2) == .success, "CoreMIDI virtual endpoint receives output")
    let unknownSysEx = event(.systemExclusive([0xF0, 0x01, 0x02, 0xF7]))
    var replayedUnknownSysEx = false
    transport.onEvent = { event in if case .systemExclusive = event.message { replayedUnknownSysEx = true } }
    try transport.replay([unknownSysEx])
    try check(!replayedUnknownSysEx, "unknown SysEx excluded from automatic replay")
    MIDIEndpointDispose(virtualDestination)
    virtualDestination = 0
    transport.refreshEndpoints()
    try check(transport.selectedDestination == nil, "removed endpoint expires connection")
    transport.close()

    var silentDestination = MIDIEndpointRef()
    try check(MIDIDestinationCreateWithBlock(client, "Arranger Lab Silent Reset Destination" as CFString, &silentDestination) { _, _ in } == noErr, "silent reset virtual destination")
    defer { MIDIEndpointDispose(silentDestination) }
    var silentDestinationID: Int32 = 0
    try check(MIDIObjectGetIntegerProperty(silentDestination, kMIDIPropertyUniqueID, &silentDestinationID) == noErr, "silent reset destination Unique ID")
    let silentResetTransport = try MIDITransport()
    silentResetTransport.refreshEndpoints()
    try silentResetTransport.connect(sourceID: nil, destinationID: silentDestinationID)
    var silentResetOutputCount = 0
    silentResetTransport.onEvent = { event in
        if event.direction == .output { silentResetOutputCount += 1 }
    }
    silentResetTransport.close(sendPanic: false)
    try check(silentResetOutputCount == 0, "silent transport reset emits no Panic or Stop")
}

func reanalyzePresetPackage(at url: URL) throws {
    var experiment = try ArrLabPackage.load(from: url)
    experiment.analysis.audioEvidence = try experiment.analysis.audioEvidence.map { record in
        try AudioFileAnalyzer.evidence(for: url.appendingPathComponent(record.relativePath), preserving: record)
    }
    guard experiment.analysis.audioEvidence.count == 3 else {
        throw HarnessFailure(description: "preset package must contain A1, B and A2 audio")
    }
    let a1 = experiment.analysis.audioEvidence[0].metrics
    let b = experiment.analysis.audioEvidence[1].metrics
    let a2 = experiment.analysis.audioEvidence[2].metrics
    let distances = [
        "A1-A2": AudioAnalyzer.spectralDistance(a1, a2),
        "A1-B": AudioAnalyzer.spectralDistance(a1, b),
        "A2-B": AudioAnalyzer.spectralDistance(a2, b)
    ]
    experiment.analysis.spectralDistances = distances
    let audioPasses = PA700EvidenceRules.presetABA(a1: a1, b: b, a2: a2)
    experiment.manifest.annotations = experiment.manifest.annotations.map { annotation in
        annotation.hasPrefix("audio A-B-A spectral rule:")
            ? "audio A-B-A spectral rule: \(audioPasses ? "passed" : "failed")"
            : annotation
    }
    if audioPasses,
       let note = experiment.analysis.notes.first,
       let nameStart = note.range(of: "name=")?.upperBound,
       let nameEnd = note[nameStart...].firstIndex(of: ";") {
        let name = String(note[nameStart..<nameEnd])
        let prompt = "Displayed preset name matched captured bank/program: \(name)"
        if !experiment.analysis.manualConfirmations.contains(where: { $0.prompt == prompt && $0.confirmed }) {
            experiment.analysis.manualConfirmations.append(.init(prompt: prompt, confirmed: true, note: note))
        }
    }
    let allPassed = experiment.manifest.annotations.allSatisfy { $0.hasSuffix(": passed") }
    experiment.manifest.mappingStatus = allPassed ? .verified : .draft
    experiment.manifest.updatedAt = Date()
    try ArrLabPackage.save(experiment, to: url)
    print("PRESET REANALYSIS: \(experiment.manifest.mappingStatus.rawValue)")
    for key in distances.keys.sorted() { print("\(key)=\(String(format: "%.6f", distances[key] ?? 0))") }
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "reanalyze-preset" {
    do { try reanalyzePresetPackage(at: URL(fileURLWithPath: CommandLine.arguments[2])) }
    catch { fputs("\nFAIL  \(error)\n", stderr); exit(1) }
} else {
    do {
        try run()
        print("\nARRANGER LAB HARNESS: \(passed) checks passed")
    } catch {
        fputs("\nFAIL  \(error)\n", stderr)
        exit(1)
    }
}
