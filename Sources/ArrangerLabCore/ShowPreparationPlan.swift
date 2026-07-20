import Foundation

public struct BundledShowBlockEntry: Codable, Equatable, Sendable {
    public let presetID: UUID
    public let catalogSongID: String?
    public let songTitle: String
    public let originalKey: String
    public let transposeSemitones: Int
    public let upper1Sound: String
    public let soundLibrary: String
}

public struct BundledShowBlockPlan: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let blockID: String
    public let parentCatalogID: String
    public let name: String
    public let setListID: UUID
    public let entries: [BundledShowBlockEntry]

    public static func showboatJul23PianoBlockA() throws -> BundledShowBlockPlan {
        guard let url = Bundle.module.url(
            forResource: "showboat-jul-23-piano-block-a",
            withExtension: "json"
        ) else {
            throw ArrangerLabError.corruptCapture("bundled Showboat Jul 23 Piano Block A plan is missing")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let plan = try decoder.decode(BundledShowBlockPlan.self, from: Data(contentsOf: url))
        guard plan.schemaVersion == 1, plan.entries.count == 10 else {
            throw ArrangerLabError.corruptCapture("bundled Showboat Jul 23 Piano Block A plan is invalid")
        }
        return plan
    }

    public static func allBundled() throws -> [BundledShowBlockPlan] {
        [try showboatJul23PianoBlockA()]
    }

    public func merging(
        presets existingPresets: [ShowPreset],
        setLists existingSetLists: [ShowSetList],
        applyOperationalDefaults: Bool,
        now: Date = Date()
    ) -> (presets: [ShowPreset], setLists: [ShowSetList], importedCount: Int) {
        var presets = existingPresets
        var importedCount = 0
        var resolvedPresetIDs: [UUID] = []
        var usedPresetIDs = Set(presets.map(\.id))

        for entry in entries {
            let sourceIndex = entry.catalogSongID.flatMap { songID in
                presets.firstIndex { preset in
                    preset.source?.catalogID == parentCatalogID
                        && preset.source?.catalogSongID == songID
                }
            }
            let localIndex = presets.firstIndex { preset in
                preset.source == nil && normalizedShowTitle(preset.songTitle) == normalizedShowTitle(entry.songTitle)
            }

            if let index = sourceIndex ?? localIndex {
                var preset = presets[index]
                if applyOperationalDefaults {
                    let previous = preset
                    preset.originalKey = entry.originalKey
                    preset.transposeSemitones = entry.transposeSemitones
                    preset.parts = Self.parts(for: entry)
                    preset.notes = Self.notes(existing: preset.notes, planName: name, library: entry.soundLibrary)
                    if !preset.hasSameOperationalReference(as: previous) {
                        preset.confirmedAt = nil
                    }
                    if preset != previous {
                        preset.updatedAt = now
                        presets[index] = preset
                    }
                }
                resolvedPresetIDs.append(preset.id)
            } else {
                let id = usedPresetIDs.contains(entry.presetID) ? UUID() : entry.presetID
                let preset = ShowPreset(
                    id: id,
                    songTitle: entry.songTitle,
                    transposeSemitones: entry.transposeSemitones,
                    parts: Self.parts(for: entry),
                    notes: Self.notes(existing: "", planName: name, library: entry.soundLibrary),
                    originalKey: entry.originalKey,
                    createdAt: now,
                    updatedAt: now
                )
                presets.append(preset)
                usedPresetIDs.insert(id)
                resolvedPresetIDs.append(id)
                importedCount += 1
            }
        }

        var setLists = existingSetLists
        if let index = setLists.firstIndex(where: {
            $0.sourceCatalogID == blockID || normalizedShowTitle($0.name) == normalizedShowTitle(name)
        }) {
            var setList = setLists[index]
            var changed = false
            if setList.sourceCatalogID != blockID {
                setList.sourceCatalogID = blockID
                changed = true
            }
            let existingByPresetID = Dictionary(uniqueKeysWithValues: setList.items.map { ($0.presetID, $0) })
            let desiredItems = resolvedPresetIDs.map { presetID in
                existingByPresetID[presetID] ?? ShowSetListItem(presetID: presetID)
            }
            if applyOperationalDefaults, setList.items != desiredItems {
                setList.items = desiredItems
                changed = true
            } else if !applyOperationalDefaults {
                let present = Set(setList.items.map(\.presetID))
                let missing = desiredItems.filter { !present.contains($0.presetID) }
                if !missing.isEmpty {
                    setList.items.append(contentsOf: missing)
                    changed = true
                }
            }
            if changed {
                setList.updatedAt = now
                setLists[index] = setList
            }
        } else {
            let id = setLists.contains(where: { $0.id == setListID }) ? UUID() : setListID
            setLists.append(
                ShowSetList(
                    id: id,
                    name: name,
                    items: resolvedPresetIDs.map { ShowSetListItem(presetID: $0) },
                    sourceCatalogID: blockID,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        return (presets, setLists, importedCount)
    }

    private static func parts(for entry: BundledShowBlockEntry) -> [ShowPresetPart] {
        [
            ShowPresetPart(
                part: .upper1,
                displayName: entry.upper1Sound,
                isEnabled: true,
                soundID: nil,
                soundLibrary: entry.soundLibrary
            ),
            ShowPresetPart(part: .upper2, displayName: "Desligado", isEnabled: false),
            ShowPresetPart(part: .upper3, displayName: "Desligado", isEnabled: false),
            ShowPresetPart(part: .lower, displayName: "Desligado", isEnabled: false)
        ]
    }

    private static func notes(existing: String, planName: String, library: String) -> String {
        let marker = "\(planName) · \(library)"
        let current = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.localizedCaseInsensitiveContains(marker) else { return current }
        return current.isEmpty ? marker : "\(current)\n\(marker)"
    }
}

private func normalizedShowTitle(_ value: String) -> String {
    value
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}
