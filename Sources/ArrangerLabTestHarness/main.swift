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
    try check(styleCatalog.styles.count == 379, "official PA700 factory Style catalog has 379 unique entries")
    try check(Set(styleCatalog.styles.map(\.address)).count == 379, "factory Style MIDI addresses are unique")
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
    let target = try KeyboardPartTarget(zone: .right, layer: 1)
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
    try check(driver.identify(from: identity).confidence == 1, "PA700 universal identity match")

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
