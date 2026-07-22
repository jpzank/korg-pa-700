import ArrangerLabCore
import SwiftUI

private enum GuideStep: Int, CaseIterable, Identifiable {
    case connection = 1
    case identity
    case input
    case output
    case preset
    case volume
    case presetABA
    case arrangerTransport
    case songBook

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .connection: return "Conectar"
        case .identity: return "Identificar"
        case .input: return "Tocar e receber"
        case .output: return "Ouvir uma nota"
        case .preset: return "Configurar o PA700"
        case .volume: return "Medir volume"
        case .presetABA: return "Descobrir timbre"
        case .arrangerTransport: return "Iniciar e parar ritmo"
        case .songBook: return "Selecionar SongBook"
        }
    }
}

struct GuideView: View {
    @EnvironmentObject var model: AppModel
    @State private var step: GuideStep = .connection
    @State private var presetAName = ""
    @State private var presetBName = ""
    @State private var songBookName = ""

    private func complete(_ candidate: GuideStep) -> Bool {
        switch candidate {
        case .connection: return model.connected
        case .identity: return model.identityVerified
        case .input: return model.inputConfirmed
        case .output: return model.outputConfirmed
        case .preset: return model.presetConfigured
        case .volume: return model.partVolumeVerified
        case .presetABA: return model.devicePresetVerified
        case .arrangerTransport: return model.arrangerTransportVerified
        case .songBook: return model.songBookVerified
        }
    }

    private var completedCount: Int { GuideStep.allCases.filter(complete).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Testes guiados", subtitle: "Siga uma etapa por vez. O app não envia SysEx desconhecido nem altera firmware ou memória.")
            HStack(spacing: 12) {
                ProgressView(value: Double(completedCount), total: Double(GuideStep.allCases.count)).frame(maxWidth: 280)
                Text("\(completedCount) de \(GuideStep.allCases.count) etapas concluídas").foregroundStyle(.secondary)
                Spacer()
                Button("Salvar evidências") { model.saveExperiment() }.disabled(completedCount == 0)
            }
            Divider()
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 4) {
                    ForEach(GuideStep.allCases) { candidate in
                        Button { step = candidate } label: {
                            HStack(spacing: 10) {
                                Image(systemName: complete(candidate) ? "checkmark.circle.fill" : "\(candidate.rawValue).circle")
                                    .foregroundStyle(complete(candidate) ? LabTheme.verified : .secondary)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.title).fontWeight(step == candidate ? .semibold : .regular)
                                    Text(complete(candidate) ? "Concluído" : candidate == step ? "Em andamento" : "Pendente").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if step == candidate { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                            }.contentShape(Rectangle()).padding(.horizontal, 10).padding(.vertical, 8)
                        }.buttonStyle(.plain).background(step == candidate ? LabTheme.signal.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                }.frame(width: 210)
                Divider()
                ScrollView { stepContent.frame(maxWidth: 680, alignment: .leading).padding(.bottom, 24) }
            }
        }
    }

    @ViewBuilder private var stepContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch step {
            case .connection:
                StepTitle(number: 1, title: "Conecte o cabo USB", detail: "O PA700 precisa aparecer nos dois sentidos.", isComplete: complete(.connection))
                CheckLine(ok: model.transport?.selectedSource?.name.contains("Pa700 KEYBOARD") == true, text: "Entrada: Pa700 KEYBOARD")
                CheckLine(ok: model.transport?.selectedDestination?.name.contains("Pa700 SOUND") == true, text: "Saída: Pa700 SOUND")
                if !model.connected { Button("Localizar e conectar PA700") { model.autoConnect() }.buttonStyle(.borderedProminent) }
                NextButton(enabled: complete(.connection)) { step = .identity }
            case .identity:
                StepTitle(number: 2, title: "Confirme o modelo", detail: "Envia somente a consulta universal segura.", isComplete: complete(.identity))
                Text(model.identityResult).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Button(model.identityVerified ? "Consultar novamente" : "Consultar identidade") { model.queryIdentity() }.disabled(!model.connected)
                NextButton(enabled: complete(.identity)) { step = .input }
            case .input:
                StepTitle(number: 3, title: "Toque três notas", detail: "Toque e solte qualquer acorde no PA700. Não é preciso clicar em gravar.", isComplete: complete(.input))
                HStack(alignment: .firstTextBaseline) { Text("\(model.receivedNoteOnCount)").font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit(); Text("Note On recebidos nesta sessão").foregroundStyle(.secondary) }
                if complete(.input) {
                    Label(model.receivedNoteOnCount > 0 ? "PA700 → Mac funcionando" : "PA700 → Mac validado em evidência anterior", systemImage: "checkmark.circle.fill").foregroundStyle(LabTheme.verified)
                }
                Button("Abrir Monitor MIDI") { model.section = .monitor }
                NextButton(enabled: complete(.input)) { step = .output }
            case .output:
                StepTitle(number: 4, title: "Ouça uma nota curta", detail: "O app envia C4 no canal 1 por 350 ms e garante Note Off.", isComplete: complete(.output))
                Button("Tocar C4 agora", systemImage: "music.note") { model.sendNote(channel: 1, note: 60, velocity: 80) }.buttonStyle(.borderedProminent).disabled(!model.connected)
                Text("Você ouviu a nota no PA700?").fontWeight(.semibold)
                HStack { Button("Sim, ouvi") { model.confirmOutputNote(heard: true) }; Button("Não ouvi") { model.confirmOutputNote(heard: false) } }
                if model.previousOutputConfirmed && !model.outputNoteHeard { Label("Saída audível confirmada na verificação salva", systemImage: "checkmark.circle.fill").foregroundStyle(LabTheme.verified) }
                if model.outputNoteFailed { Label("Confira o Master Volume, se Upper1 está ativo e se MIDI IN canal 1 está em Upper1.", systemImage: "wrench.and.screwdriver").foregroundStyle(LabTheme.draft) }
                NextButton(enabled: complete(.output)) { step = .preset }
            case .preset:
                StepTitle(number: 5, title: "Crie o preset ArrangerLab", detail: "Esta etapa é feita na tela do PA700. Não sobrescreva nenhum preset existente.", isComplete: complete(.preset))
                Instruction(number: 1, text: "No PA700, abra GLOBAL > MIDI > MIDI IN Channels.")
                Instruction(number: 2, text: "Defina: 1 Upper1, 2 Upper2, 3 Upper3, 4 Lower, 16 Control. Deixe os demais Off.")
                Instruction(number: 3, text: "Em MIDI OUT Channels, use as mesmas partes nos canais 1, 2, 3, 4 e 16.")
                Instruction(number: 4, text: "Em Filters, deixe os oito filtros MIDI In e MIDI Out em Off.")
                Instruction(number: 5, text: "No menu da página, escolha Write Midi Preset, selecione o primeiro slot vazio, nomeie ArrangerLab e confirme.")
                if model.previousPresetConfirmed && !model.midiPresetConfirmed {
                    Label("Preset ArrangerLab confirmado na verificação salva", systemImage: "checkmark.circle.fill").foregroundStyle(LabTheme.verified)
                } else {
                    Button("Já configurei exatamente assim") { model.confirmMIDIPreset() }.buttonStyle(.borderedProminent)
                }
                NextButton(enabled: complete(.preset)) { step = .volume }
            case .volume:
                StepTitle(number: 6, title: "Meça três volumes", detail: "O MacBook grava clipes curtos enquanto o PA700 toca a mesma sequência.", isComplete: complete(.volume))
                if model.persistedPartVolumeVerified {
                    Label("Mapping partVolume Verified e liberado para uso operacional", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(LabTheme.verified)
                    if model.persistedVolumeRMSDBFS.count == 3 {
                        Text("25%  \(model.persistedVolumeRMSDBFS[0], specifier: "%.1f") dBFS   •   50%  \(model.persistedVolumeRMSDBFS[1], specifier: "%.1f") dBFS   •   75%  \(model.persistedVolumeRMSDBFS[2], specifier: "%.1f") dBFS")
                            .font(.system(.body, design: .monospaced))
                    }
                    Text("RMS estritamente crescente, diferença total de pelo menos 6 dB e confirmação física registrada.").foregroundStyle(.secondary)
                    if let url = model.lastSavedExperimentURL { Text(url.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
                } else {
                    Text("Fique em silêncio durante cada medição e não toque no teclado.").fontWeight(.semibold)
                    EvidenceAction(title: "Calibrar silêncio, 2 s", value: model.silenceEvidence?.metrics.rmsDBFS, done: model.silenceEvidence != nil, disabled: model.activeGuideAction != nil) { model.recordSilenceCalibration() }
                    ForEach([25, 50, 75], id: \.self) { level in
                        EvidenceAction(title: "Medir \(level)%", value: model.volumeEvidenceByLevel[level]?.metrics.rmsDBFS, done: model.volumeEvidenceByLevel[level] != nil, disabled: model.activeGuideAction != nil || model.silenceEvidence == nil || !model.midiPresetConfirmed) { model.recordVolumeEvidence(level: level) }
                    }
                    if let action = model.activeGuideAction { ProgressView().controlSize(.small); Text(action).foregroundStyle(.secondary) }
                    if model.volumeEvidenceByLevel.count == 3 {
                        Label(model.volumeEvidencePasses ? "RMS crescente e diferença total de pelo menos 6 dB" : "As medições não passaram; repita num ambiente mais silencioso", systemImage: model.volumeEvidencePasses ? "checkmark.circle.fill" : "arrow.clockwise.circle")
                            .foregroundStyle(model.volumeEvidencePasses ? LabTheme.verified : LabTheme.draft)
                        Button("Confirmar e salvar verificação") { model.confirmVolumeAndSave() }.disabled(!model.volumeEvidencePasses || model.partVolumeVerified)
                    }
                }
                NextButton(enabled: complete(.volume)) { step = .presetABA }
            case .presetABA:
                StepTitle(number: 7, title: "Descubra um timbre exato", detail: "O PA700 envia CC0, CC32 e PC; o app grava A, B e A com a mesma sequência.", isComplete: complete(.presetABA))
                if model.devicePresetVerified {
                    Label("Mapping devicePreset Verified", systemImage: "checkmark.seal.fill").foregroundStyle(LabTheme.verified)
                    if !model.persistedPresetSummary.isEmpty { Text(model.persistedPresetSummary).font(.system(.body, design: .monospaced)) }
                    if !model.presetABADistances.isEmpty {
                        Text("Distâncias: A1/A2 \(model.presetABADistances["A1-A2"] ?? 0, specifier: "%.4f")  •  A1/B \(model.presetABADistances["A1-B"] ?? 0, specifier: "%.4f")  •  A2/B \(model.presetABADistances["A2-B"] ?? 0, specifier: "%.4f")")
                            .font(.system(.caption, design: .monospaced))
                    }
                    if let url = model.presetExperimentURL { Text(url.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
                    Button("Fazer uma nova medição") { model.resetPresetABA() }
                } else {
                    Text("Use somente o Upper1. Depois de clicar em Preparar, escolha o timbre no painel do PA700 e volte ao app para capturar.").fontWeight(.semibold)
                    TextField("Nome exato do timbre A mostrado no PA700", text: $presetAName).textFieldStyle(.roundedBorder).frame(maxWidth: 440)
                    PresetPhaseControl(phase: .a1, displayedName: presetAName, enabled: true)
                    Divider().frame(maxWidth: 520)
                    TextField("Nome exato do timbre B mostrado no PA700", text: $presetBName).textFieldStyle(.roundedBorder).frame(maxWidth: 440)
                    PresetPhaseControl(phase: .b, displayedName: presetBName, enabled: model.presetAudioEvidence[.a1] != nil)
                    Divider().frame(maxWidth: 520)
                    Text("A2 deve mostrar novamente: \(presetAName.isEmpty ? "o mesmo nome de A" : presetAName)").foregroundStyle(.secondary)
                    PresetPhaseControl(phase: .a2, displayedName: presetAName, enabled: model.presetAudioEvidence[.b] != nil)
                    if let action = model.activeGuideAction { HStack { ProgressView().controlSize(.small); Text(action).foregroundStyle(.secondary) } }
                    if !model.devicePresetVerificationChecks.isEmpty {
                        ForEach(model.devicePresetVerificationChecks.keys.sorted(), id: \.self) { key in
                            CheckLine(ok: model.devicePresetVerificationChecks[key] == true, text: key)
                        }
                        if let url = model.presetExperimentURL { Text("Evidência Draft: \(url.path)").font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                }
                NextButton(enabled: complete(.presetABA)) { step = .arrangerTransport }
            case .arrangerTransport:
                StepTitle(number: 8, title: "Inicie e pare o Arranger", detail: "O Mac envia Clock a 120 BPM, Start e Stop; o PA700 deve estar temporariamente em External USB.", isComplete: complete(.arrangerTransport))
                if model.arrangerTransportVerified {
                    Label("Mapping arrangerTransport Verified", systemImage: "checkmark.seal.fill").foregroundStyle(LabTheme.verified)
                    Text("Clock Source foi restaurado para Internal após o teste.").foregroundStyle(.secondary)
                    if let url = model.arrangerTransportExperimentURL {
                        Text(url.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                } else {
                    if model.clockRestoreRequired {
                        Label("Atenção: restaure Clock Source = Internal antes de sair deste teste", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(LabTheme.draft)
                            .fontWeight(.semibold)
                    }
                    Instruction(number: 1, text: "No PA700, pressione STYLE PLAY.")
                    Instruction(number: 2, text: "Abra GLOBAL > MIDI > General Controls.")
                    Instruction(number: 3, text: "Em Clock Source, escolha External USB. Não ative Clock Send.")
                    if !model.arrangerExternalUSBConfirmed || !model.clockRestoreRequired {
                        Button("Clock Source está em External USB") { model.confirmArrangerExternalUSB() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.connected || !model.identityVerified || !model.presetConfigured)
                    } else {
                        CheckLine(ok: true, text: "External USB confirmado")
                    }

                    if model.arrangerExternalUSBConfirmed && model.clockRestoreRequired && !model.arrangerClockRunning && !model.arrangerStopSent {
                        Text("Ao clicar, o acompanhamento pode começar imediatamente. Deixe tocar por pelo menos 3 segundos.").fontWeight(.semibold)
                        Button("Start a 120 BPM", systemImage: "play.fill") { model.startGuidedArrangerClock() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.activeGuideAction != nil)
                    }
                    if model.arrangerClockRunning {
                        Label("Clock ativo: 120 BPM", systemImage: "waveform.path.ecg").foregroundStyle(LabTheme.verified)
                        Text("O acompanhamento começou no PA700?").fontWeight(.semibold)
                        HStack {
                            Button("Sim, começou") { model.confirmArrangerStarted(heard: true) }
                            Button("Não começou") { model.confirmArrangerStarted(heard: false) }
                        }
                        Button("Stop + Panic", systemImage: "stop.fill") { model.stopGuidedArrangerClock() }
                            .buttonStyle(.borderedProminent)
                            .tint(LabTheme.danger)
                    }
                    if model.arrangerStopSent && !model.arrangerClockRunning {
                        Text("O acompanhamento parou?").fontWeight(.semibold)
                        HStack {
                            Button("Sim, parou") { model.confirmArrangerStopped(heard: true) }
                            Button("Ainda está tocando") { model.confirmArrangerStopped(heard: false) }
                        }
                    }
                    if model.clockRestoreRequired && !model.arrangerClockRunning {
                        Divider().frame(maxWidth: 560)
                        Instruction(number: 4, text: "No mesmo menu do PA700, volte Clock Source para Internal.")
                        Button("Clock Source voltou para Internal") { model.confirmArrangerInternalRestored() }
                            .buttonStyle(.borderedProminent)
                    }
                    if let action = model.activeGuideAction {
                        HStack { ProgressView().controlSize(.small); Text(action).foregroundStyle(.secondary) }
                    }
                    if !model.arrangerTransportChecks.isEmpty {
                        Divider().frame(maxWidth: 560)
                        ForEach(model.arrangerTransportChecks.keys.sorted(), id: \.self) { key in
                            CheckLine(ok: model.arrangerTransportChecks[key] == true, text: key)
                        }
                        Button("Confirmar e salvar verificação") { model.saveArrangerTransportVerification() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.arrangerTransportPasses)
                    }
                }
                NextButton(enabled: complete(.arrangerTransport)) { step = .songBook }
            case .songBook:
                StepTitle(number: 9, title: "Selecione uma entrada do SongBook", detail: "O app envia NRPN e Data Entry no canal Control 16 para chamar a entrada dedicada 9000.", isComplete: complete(.songBook))
                if model.songBookVerified {
                    Label("Mapping songBook Verified", systemImage: "checkmark.seal.fill").foregroundStyle(LabTheme.verified)
                    Text("9000 · \(model.songBookDisplayedName.isEmpty ? "ArrangerLab Test" : model.songBookDisplayedName)")
                        .font(.system(.body, design: .monospaced))
                    if let url = model.songBookExperimentURL {
                        Text(url.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                } else {
                    Instruction(number: 1, text: "No PA700, pressione STYLE PLAY. A entrada ArrangerLab Test deve existir com número 9000.")
                    if !model.songBookStylePlayConfirmed {
                        Button("Estou em Style Play") { model.confirmSongBookStylePlay() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.connected || !model.identityVerified || !model.presetConfigured)
                    } else {
                        CheckLine(ok: true, text: "Style Play confirmado")
                    }
                    Instruction(number: 2, text: "O envio será: BF 63 02 · BF 62 40 · BF 06 5A · BF 26 00.")
                    if model.songBookStylePlayConfirmed && model.songBookSentNumber == nil {
                        Button("Selecionar SongBook 9000", systemImage: "music.note.list") { model.sendGuidedSongBook(9_000) }
                            .buttonStyle(.borderedProminent)
                    }
                    if model.songBookSentNumber == 9_000 {
                        CheckLine(ok: true, text: "Comando para 9000 enviado no canal 16")
                        Text("Qual nome apareceu como entrada selecionada no PA700?").fontWeight(.semibold)
                        TextField("Nome exato mostrado", text: $songBookName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 440)
                        Button("Sim, apareceu esta entrada") { model.confirmGuidedSongBook(displayedName: songBookName) }
                            .disabled(songBookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if !model.songBookVerificationChecks.isEmpty {
                        Divider().frame(maxWidth: 560)
                        ForEach(model.songBookVerificationChecks.keys.sorted(), id: \.self) { key in
                            CheckLine(ok: model.songBookVerificationChecks[key] == true, text: key)
                        }
                        Button("Confirmar e salvar verificação") { model.saveSongBookVerification() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.songBookPasses)
                    }
                }
            }
        }
    }
}

private struct StepTitle: View {
    let number: Int, title: String, detail: String, isComplete: Bool
    var body: some View { HStack(alignment: .top, spacing: 12) { Image(systemName: isComplete ? "checkmark.circle.fill" : "\(number).circle.fill").font(.title).foregroundStyle(isComplete ? LabTheme.verified : LabTheme.signal); VStack(alignment: .leading, spacing: 4) { Text(title).font(.title2.weight(.semibold)); Text(detail).foregroundStyle(.secondary) } } }
}

private struct CheckLine: View {
    let ok: Bool, text: String
    var body: some View { Label(text, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(ok ? LabTheme.verified : .secondary) }
}

private struct Instruction: View {
    let number: Int, text: String
    var body: some View { HStack(alignment: .top, spacing: 10) { Text(String(number)).font(.caption.weight(.bold)).frame(width: 22, height: 22).background(.quaternary, in: Circle()); Text(text).fixedSize(horizontal: false, vertical: true) } }
}

private struct NextButton: View {
    let enabled: Bool, action: () -> Void
    var body: some View { Button("Próxima etapa", systemImage: "arrow.right", action: action).buttonStyle(.borderedProminent).disabled(!enabled).padding(.top, 6) }
}

private struct EvidenceAction: View {
    let title: String, value: Double?, done: Bool, disabled: Bool, action: () -> Void
    var body: some View { HStack { Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? LabTheme.verified : .secondary); Button(title, action: action).disabled(disabled || done); Spacer(); if let value { Text("\(value, specifier: "%.1f") dBFS").font(.system(.body, design: .monospaced)) } }.frame(maxWidth: 460) }
}

private struct PresetPhaseControl: View {
    @EnvironmentObject var model: AppModel
    let phase: AppModel.PresetABAPhase
    let displayedName: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.presetAudioEvidence[phase] == nil ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(model.presetAudioEvidence[phase] == nil ? .secondary : LabTheme.verified)
            VStack(alignment: .leading, spacing: 2) {
                Text(phase.instruction).fontWeight(.semibold)
                if let selection = model.presetSelections[phase] {
                    Text(selection.display).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.pendingPresetPhase == phase {
                Button("Capturar \(phase.rawValue) agora") { model.capturePresetPhase(phase, displayedName: displayedName) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!enabled || model.activeGuideAction != nil || model.presetAudioEvidence[phase] != nil)
            } else {
                Button("Preparar \(phase.rawValue)") { model.preparePresetCapture(phase) }
                    .buttonStyle(.bordered)
                    .disabled(!enabled || model.activeGuideAction != nil || model.presetAudioEvidence[phase] != nil)
            }
        }.frame(maxWidth: 620)
    }
}
