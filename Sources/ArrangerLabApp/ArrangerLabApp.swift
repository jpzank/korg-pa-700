import ArrangerLabCore
import AppKit
import SwiftUI

@main
struct ArrangerLabApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("Show", id: "show") {
            ShowView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 640)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.terminate() }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                    model.resetPA700Connection()
                }
        }
            .defaultSize(width: 1_220, height: 780)
            .commands { ArrangerLabCommands(model: model) }
            .onChange(of: scenePhase) { _, phase in if phase == .background { model.panic() } }

        Window("Laboratório", id: "laboratory") {
            LaboratoryRootView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 660)
        }
            .defaultSize(width: 1_220, height: 780)
    }
}

private struct ArrangerLabCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let model: AppModel

    var body: some Commands {
        CommandMenu("Arranger Lab") {
            Button("Show") {
                model.showWorkspaceMode = .show
                openWindow(id: "show")
            }
                .keyboardShortcut("1", modifiers: [.command])
            Button("Repertório") {
                model.showWorkspaceMode = .repertoire
                openWindow(id: "show")
            }
                .keyboardShortcut("2", modifiers: [.command])
            Button("Abrir Laboratório") { openWindow(id: "laboratory") }
                .keyboardShortcut("3", modifiers: [.command])
            Divider()
            Button("Panic") { model.panic() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
        }
    }
}

struct LaboratoryRootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            ConnectionStrip()
            Divider()
            NavigationSplitView {
                List(AppModel.Section.allCases, selection: $model.section) { section in
                    Label(section.rawValue, systemImage: section.icon).tag(section)
                }.navigationSplitViewColumnWidth(min: 190, ideal: 220)
            } detail: {
                Group {
                    switch model.section {
                    case .performance: PerformanceView()
                    case .batchMapping: BatchMappingView()
                    case .guide: GuideView()
                    case .connection: ConnectionView()
                    case .monitor: MonitorView()
                    case .send: SendView()
                    case .recorder: RecorderView()
                    case .experiments: ExperimentsView()
                    }
                }
                .padding(LabTheme.page)
            }
        }
        .tint(LabTheme.signal)
        .alert("Arranger Lab", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) { Button("OK") { model.lastError = nil } } message: { Text(model.lastError ?? "") }
    }
}

struct ConnectionStrip: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: LabTheme.control) {
            Image(systemName: model.connected ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(model.connected ? LabTheme.verified : .secondary)
                .accessibilityLabel(model.connected ? "Conectado" : "Desconectado")
            VStack(alignment: .leading, spacing: 1) {
                Text(model.connected ? "PA700 conectado via USB" : "Nenhum teclado conectado").fontWeight(.semibold)
                Text(model.section == .performance ? (model.connected ? model.performanceStatus : "Conecte o teclado para começar") : model.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(model.profile.model).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            Button("Panic", systemImage: "exclamationmark.octagon.fill") { model.panic() }.buttonStyle(.borderedProminent).tint(LabTheme.danger).keyboardShortcut(".", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 18)
        .frame(height: LabTheme.statusStripHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct PageHeader: View {
    let title: String; let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ConnectionView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Conexão", subtitle: "Endpoints são persistidos por CoreMIDI Unique ID e atualizados no hot-plug.")
            Form {
                Picker("Entrada", selection: $model.selectedSourceID) { Text("Nenhuma").tag(Int32?.none); ForEach(model.sources) { Text("\($0.name) · \($0.id)").tag(Optional($0.id)) } }
                Picker("Saída", selection: $model.selectedDestinationID) { Text("Nenhuma").tag(Int32?.none); ForEach(model.destinations) { Text("\($0.name) · \($0.id)").tag(Optional($0.id)) } }
                HStack { Button("Conectar") { model.connect() }.buttonStyle(.borderedProminent); Button("Localizar PA700") { model.autoConnect() }; Button("Desconectar") { model.disconnect() }.disabled(!model.connected) }
            }.formStyle(.grouped)
            GroupBox("Identidade universal") { HStack { VStack(alignment: .leading) { Text(model.identityResult); Text("Consulta: F0 7E 7F 06 01 F7").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }; Spacer(); Button("Consultar") { model.queryIdentity() }.disabled(!model.connected) }.padding(8) }
            GroupBox("Preset MIDI ArrangerLab: configuração física") {
                VStack(alignment: .leading, spacing: 7) { Text("Crie no primeiro slot vazio; nunca sobrescreva um preset.").fontWeight(.semibold); Text("Ch 1 Upper1 · Ch 2 Upper2 · Ch 3 Upper3 · Ch 4 Lower · Ch 16 Control"); Text("Libere CC, PC e apenas SysEx conhecidos. Firmware permanece em 1.5.0.").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            Spacer()
        }
    }
}

struct MonitorView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        MonitorContent(model: model, monitor: model.midiMonitor)
    }
}

private struct MonitorContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var monitor: MIDIMonitorState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Monitor", subtitle: "Filtros escondem ruído visual sem alterar os bytes capturados.")
            HStack { Toggle("Ocultar Clock", isOn: $model.filterClock); Toggle("Ocultar Active Sensing", isOn: $model.filterActiveSensing); Spacer(); Text("\(monitor.totalEventCount) crus · \(model.visibleEvents.count) visíveis no buffer").foregroundStyle(.secondary); Button("Limpar") { model.clearEvents() } }
            Table(model.visibleEvents.suffix(2_000).reversed()) {
                TableColumn("Tempo +s") { event in Text(model.elapsedString(for: event)).font(.system(.caption, design: .monospaced)) }.width(90)
                TableColumn("Direção") { event in Label(event.direction == .input ? "IN" : "OUT", systemImage: event.direction == .input ? "arrow.down.left" : "arrow.up.right").foregroundStyle(event.direction == .input ? LabTheme.inbound : LabTheme.draft) }.width(75)
                TableColumn("Mensagem") { event in Text(event.message?.displayName ?? "Bruta") }.width(130)
                TableColumn("Endpoint") { event in Text(event.endpointName) }.width(min: 140)
                TableColumn("Bytes") { event in Text(event.hex).font(.system(.body, design: .monospaced)).textSelection(.enabled) }
            }
        }
    }
}

struct SendView: View {
    @EnvironmentObject var model: AppModel
    @State private var channel = 1; @State private var controller = 7; @State private var value = 95; @State private var program = 0; @State private var note = 60; @State private var velocity = 80
    @State private var typedModel = ""; @State private var sysEx = "F0 7E 7F 06 01 F7"; @State private var confirmSysEx = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Envio", subtitle: "Mensagens comuns permanecem simples; SysEx arbitrário exige Expert e confirmação dupla.")
            HStack(alignment: .top, spacing: 18) {
                Form {
                    Stepper("Canal: \(channel)", value: $channel, in: 1...16)
                    Stepper("CC: \(controller)", value: $controller, in: 0...127)
                    Stepper("Valor: \(value)", value: $value, in: 0...127)
                    Button("Enviar CC") { model.sendCC(channel: channel, controller: controller, value: value) }
                    Divider(); Stepper("Programa: \(program)", value: $program, in: 0...127); Button("Enviar PC") { model.sendPC(channel: channel, program: program) }
                    Divider(); Stepper("Nota: \(note)", value: $note, in: 0...127); Stepper("Velocity: \(velocity)", value: $velocity, in: 1...127); Button("Tocar 3 segundos") { model.sendNote(channel: channel, note: note, velocity: velocity, durationMilliseconds: 3_000) }
                }.formStyle(.grouped).frame(maxWidth: 430)
                GroupBox("Modo Expert") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.expert.isUnlocked ? "Ativo; expira ao desconectar ou fechar" : "Digite exatamente o modelo conectado.")
                            .foregroundStyle(model.expert.isUnlocked ? LabTheme.verified : .secondary)
                        HStack { TextField("PA700", text: $typedModel); Button("Desbloquear") { model.unlockExpert(typedModel: typedModel) } }
                        Text("Destino: \(model.transport?.selectedDestination?.name ?? "nenhum")").font(.caption)
                        TextField("Bytes SysEx", text: $sysEx).font(.system(.body, design: .monospaced)).disabled(!model.expert.isUnlocked)
                        Toggle("Confirmo o envio destes bytes completos", isOn: $confirmSysEx).disabled(!model.expert.isUnlocked)
                        Button("Enviar SysEx arbitrário") { model.sendSysEx(hex: sysEx, confirmed: confirmSysEx) }.buttonStyle(.borderedProminent).tint(LabTheme.danger).disabled(!model.expert.isUnlocked || !confirmSysEx)
                        Text("SysEx desconhecido nunca entra em reprodução automática.").font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
            }
            Spacer()
        }
    }
}

struct RecorderView: View {
    @EnvironmentObject var model: AppModel
    @State private var includeNotes = false; @State private var includeClock = false; @State private var includeSensing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Captura e comparação", subtitle: "A reprodução usa somente eventos de saída e sempre termina com Panic.")
            GroupBox("Identificar painel do PA700") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Picker("Observar", selection: $model.liveDiscoveryTarget) {
                            ForEach(PA700LiveDiscoveryTarget.allCases) { target in
                                Text(target.rawValue).tag(target)
                            }
                        }
                        .frame(width: 230)
                        .disabled(model.liveDiscoveryCapturing)

                        Button(
                            model.liveDiscoveryCapturing ? "Concluir repetição" : "Iniciar repetição",
                            systemImage: model.liveDiscoveryCapturing ? "stop.fill" : "record.circle"
                        ) {
                            if model.liveDiscoveryCapturing {
                                model.finishLiveDiscoverySample()
                            } else {
                                model.startLiveDiscoverySample()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(model.liveDiscoveryCapturing ? LabTheme.danger : LabTheme.signal)
                        .disabled(!model.connected)

                        let targetSamples = model.liveDiscoverySamples.filter { $0.target == model.liveDiscoveryTarget }
                        Text("\(min(targetSamples.count, 3)) de 3")
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(
                                PA700LiveDiscovery.hasThreeMatchingSamples(model.liveDiscoverySamples, for: model.liveDiscoveryTarget)
                                    ? LabTheme.verified
                                    : Color.secondary
                            )
                        Spacer()
                        Button("Limpar", action: model.clearLiveDiscoverySamples)
                            .disabled(model.liveDiscoverySamples.isEmpty || model.liveDiscoveryCapturing)
                    }
                    Text("\(model.liveDiscoveryTarget.instruction) Volte ao estado inicial antes de cada repetição.")
                        .foregroundStyle(.secondary)
                    ForEach(model.liveDiscoverySamples.filter { $0.target == model.liveDiscoveryTarget }.suffix(3)) { sample in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("R\(sample.repetition)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .frame(width: 28, alignment: .leading)
                            Text(sample.signature)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                    }
                    Text("Somente MIDI de entrada. Clock e Active Sensing são ignorados; nenhum comando é enviado ao teclado.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
            HStack { Button(model.isRecording ? "Parar" : "Gravar", systemImage: model.isRecording ? "stop.fill" : "record.circle") { model.toggleRecording() }.buttonStyle(.borderedProminent).tint(model.isRecording ? LabTheme.danger : LabTheme.signal); Button("Guardar A") { model.markCaptureA() }; Button("Guardar B") { model.markCaptureB() }; Divider().frame(height: 20); Text("Reprodução"); Slider(value: $model.replaySpeed, in: 0.25...2, step: 0.25).frame(width: 130); Text("\(model.replaySpeed, specifier: "%.2f")×").monospacedDigit(); Button("Reproduzir") { model.replayCurrent() }.disabled(!model.connected); Spacer(); Button("Salvar .arrlab") { model.saveExperiment() } }
            HStack { Toggle("Notas", isOn: $includeNotes); Toggle("Clock", isOn: $includeClock); Toggle("Active Sensing", isOn: $includeSensing); Button("Atualizar Diff") { model.updateDiff(includeNotes: includeNotes, includeClock: includeClock, includeSensing: includeSensing) }; Spacer(); Text("A \(model.captureA.count) · B \(model.captureB.count)").foregroundStyle(.secondary) }
            Table(model.diff) {
                TableColumn("Mudança") { item in Text(item.kind.rawValue.capitalized) }.width(90)
                TableColumn("Mensagem") { item in Text(item.label) }
                TableColumn("A") { item in Text(item.before ?? "Vazio").font(.system(.body, design: .monospaced)) }.width(120)
                TableColumn("B") { item in Text(item.after ?? "Vazio").font(.system(.body, design: .monospaced)) }.width(120)
            }
        }
    }
}

struct ExperimentsView: View {
    @EnvironmentObject var model: AppModel
    @State private var bankMSB = 0
    @State private var bankLSB = 0
    @State private var program = 0
    @State private var songBook = 9_000
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Experimentos e evidências", subtitle: "Todos começam como rascunho. A promoção exige bytes, firmware, configuração e confirmação física.")
            HStack { Button(model.isAudioRecording ? "Encerrar clipe" : "Gravar clipe WAV", systemImage: "mic") { model.toggleAudio() }.buttonStyle(.borderedProminent); Text("\(model.audioEvidence.count) clipes • mono 48 kHz").foregroundStyle(.secondary); Spacer() }
            List {
                ExperimentRow(number: 1, title: "Identidade", detail: "Esperado: fabricante 42 · família 0060 · modelo 005D", state: model.identityVerified ? "Verified" : "Draft", action: { model.queryIdentity() }, actionTitle: "Consultar")
                VStack(alignment: .leading, spacing: 8) {
                    ExperimentRow(number: 2, title: "Volume right/layer 1", detail: "CC7 ch 1 em 0,25 / 0,50 / 0,75; RMS crescente e ≥ 6 dB + confirmação", state: model.partVolumeVerified ? "Verified" : "Draft", action: nil, actionTitle: nil)
                    HStack { ForEach([0.25, 0.50, 0.75], id: \.self) { level in Button("\(Int(level * 100))%") { model.sendVolume(level) } }; Button("Estímulo fixo") { model.playFixedStimulus() }; Button("Confirmar volume") { model.confirm("Volume right/layer 1 audibly changed") } }.padding(.leading, 42)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ExperimentRow(number: 3, title: "Expression right/layer 1", detail: "CC11 ch 1 em 0,25 / 0,50 / 0,75; volume CC7 fixo, RMS crescente e confirmação", state: model.partExpressionOperational ? "Verified" : (model.partExpressionEvidenceReady ? "Evidence ready" : "Draft"), action: nil, actionTitle: nil)
                    HStack {
                        Button(model.silenceEvidence == nil ? "Calibrar silêncio, 2 s" : "Silêncio ✓") { model.recordSilenceCalibration() }
                            .disabled(model.activeGuideAction != nil)
                        ForEach([25, 50, 75], id: \.self) { level in
                            Button(model.expressionEvidenceByLevel[level] == nil ? "Medir \(level)%" : "\(level)% ✓") { model.recordExpressionEvidence(level: level) }
                                .disabled(model.activeGuideAction != nil || model.silenceEvidence == nil || !model.presetConfigured)
                        }
                        Button("Confirmar e salvar") { model.confirmExpressionAndSave() }
                            .disabled(!model.expressionEvidencePasses || model.partExpressionEvidenceReady)
                    }.padding(.leading, 42)
                    if let action = model.activeGuideAction { HStack { ProgressView().controlSize(.small); Text(action).foregroundStyle(.secondary) }.padding(.leading, 42) }
                    if !model.expressionEvidenceByLevel.isEmpty {
                        Text([25, 50, 75].compactMap { level in model.expressionEvidenceByLevel[level].map { "\(level)% \(String(format: "%.1f", $0.metrics.rmsDBFS)) dBFS" } }.joined(separator: "  •  "))
                            .font(.caption.monospaced()).foregroundStyle(.secondary).padding(.leading, 42)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ExperimentRow(number: 4, title: "Pan right/layer 1", detail: "CC10 ch 1: esquerda 0 · centro 64 · direita 127; confirmação estéreo física", state: model.partPanOperational ? "Verified" : (model.partPanEvidenceReady ? "Evidence ready" : "Draft"), action: nil, actionTitle: nil)
                    HStack {
                        Button(model.silenceEvidence == nil ? "Calibrar silêncio, 2 s" : "Silêncio ✓") { model.recordSilenceCalibration() }
                            .disabled(model.activeGuideAction != nil)
                        ForEach([-100, 0, 100], id: \.self) { position in
                            let label = position < 0 ? "Esquerda" : (position > 0 ? "Direita" : "Centro")
                            Button(model.panEvidenceByPosition[position] == nil ? label : "\(label) ✓") { model.recordPanEvidence(position: position) }
                                .disabled(model.activeGuideAction != nil || model.silenceEvidence == nil || !model.presetConfigured)
                        }
                        Button("Confirmar e salvar") { model.confirmPanAndSave() }
                            .disabled(!model.panAudioCaptured || model.partPanEvidenceReady)
                    }.padding(.leading, 42)
                    if model.activeGuideAction?.contains("Pan") == true { HStack { ProgressView().controlSize(.small); Text(model.activeGuideAction ?? "").foregroundStyle(.secondary) }.padding(.leading, 42) }
                    if !model.panEvidenceByPosition.isEmpty {
                        Text([-100, 0, 100].compactMap { position in
                            let label = position < 0 ? "L" : (position > 0 ? "R" : "C")
                            return model.panEvidenceByPosition[position].map { "\(label) \(String(format: "%.1f", $0.metrics.rmsDBFS)) dBFS" }
                        }.joined(separator: "  •  "))
                            .font(.caption.monospaced()).foregroundStyle(.secondary).padding(.leading, 42)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ExperimentRow(number: 5, title: "Damper / Sustain right/layer 1", detail: "Modo Sound + preset ArrangerLab; CC64 ch 1: OFF 0 · ON 127 · OFF 0", state: model.partDamperOperational ? "Verified" : (model.partDamperEvidenceReady ? "Evidence ready" : "Draft"), action: nil, actionTitle: nil)
                    HStack {
                        Button(model.damperTestCompleted ? "Sequência concluída ✓" : "Ouvir OFF / ON / OFF") { model.recordDamperEvidence() }
                            .disabled(model.activeGuideAction != nil || !model.presetConfigured || model.partDamperEvidenceReady)
                        Button("Confirmar e salvar") { model.confirmDamperAndSave() }
                            .disabled(!model.damperTestCompleted || model.partDamperEvidenceReady)
                    }.padding(.leading, 42)
                    if model.activeGuideAction?.contains("Damper") == true { HStack { ProgressView().controlSize(.small); Text(model.activeGuideAction ?? "").foregroundStyle(.secondary) }.padding(.leading, 42) }
                    if model.damperTestCompleted {
                        Text("OFF → nota seca → ON → nota sustentada → OFF  •  restaurado OFF")
                            .font(.caption.monospaced()).foregroundStyle(.secondary).padding(.leading, 42)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ExperimentRow(number: 6, title: "Preset exato A/B/A", detail: "Descobrir CC0.CC32.PC por captura; A repetido deve ser espectralmente mais próximo", state: model.devicePresetVerified ? "Verified" : "Draft", action: nil, actionTitle: nil)
                    HStack { Stepper("CC0 \(bankMSB)", value: $bankMSB, in: 0...127); Stepper("CC32 \(bankLSB)", value: $bankLSB, in: 0...127); Stepper("PC \(program)", value: $program, in: 0...127); Button("Enviar observado") { model.sendPresetLab(bankMSB: bankMSB, bankLSB: bankLSB, program: program) }; Button("Confirmar nome") { model.confirm("Displayed preset name matched captured bank/program") } }.padding(.leading, 42)
                }
                ExperimentRow(number: 7, title: "Arranger Start / Stop", detail: "Defina External USB temporariamente, clock 120 BPM + Start/Stop, depois restaure Internal", state: model.arrangerTransportVerified ? "Verified" : "Draft", action: { model.startClock() }, secondary: { model.stopClock() }, actionTitle: "Start 120 BPM")
                VStack(alignment: .leading, spacing: 8) {
                    ExperimentRow(number: 8, title: "SongBook", detail: "Ch 16: CC99=2, CC98=64, CC6/CC38; requer número existente e confirmação", state: model.songBookVerified ? "Verified" : "Draft", action: nil, actionTitle: nil)
                    HStack { Stepper("Número \(songBook)", value: $songBook, in: 0...9_999); Button("Selecionar") { model.sendSongBook(songBook) }; Button("Confirmar entrada") { model.confirm("Displayed SongBook entry matched requested number \(songBook)") } }.padding(.leading, 42)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ExperimentRow(number: 9, title: "Elementos do Arranger", detail: "Canal Control 16 · PC80 a PC94 · Intro, Variation, Fill, Break e Ending", state: "\(ArrangerElement.allCases.filter { model.profile.mappings[$0.mappingID]?.status == .verified }.count)/\(ArrangerElement.allCases.count) Verified", action: nil, actionTitle: nil)
                    HStack {
                        Menu("Enviar elemento…") {
                            ForEach(ArrangerElement.allCases, id: \.self) { element in
                                Button("\(element.displayName) · PC \(element.rawValue) · \(model.profile.mappings[element.mappingID]?.status.rawValue ?? "Draft")") { model.sendArrangerElement(element) }
                            }
                        }
                        Text("Mostra bytes completos antes da promoção").font(.caption).foregroundStyle(.secondary)
                    }.padding(.leading, 42)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ExperimentRow(number: 10, title: "Keyboard Set 1 a 4", detail: "Canal Control 16 · PC64 a PC67 · usa o Style ou SongBook selecionado", state: model.profile.mappings["keyboardSet"]?.status.rawValue ?? "Draft", action: nil, actionTitle: nil)
                    HStack {
                        ForEach(1...4, id: \.self) { slot in Button("Kbd Set \(slot)") { model.sendKeyboardSet(slot) } }
                    }.padding(.leading, 42)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ExperimentRow(number: 11, title: "Controles do Arranger / Player", detail: "Canal Control 16 · PC95 a PC104 · comandos contextuais e toggles", state: "\(ArrangerControl.allCases.filter { model.profile.mappings[$0.mappingID]?.status == .verified }.count)/\(ArrangerControl.allCases.count) Verified", action: nil, actionTitle: nil)
                    HStack {
                        Menu("Enviar controle…") {
                            ForEach(ArrangerControl.allCases, id: \.self) { control in
                                Button("\(control.displayName) · PC \(control.rawValue) · \(model.profile.mappings[control.mappingID]?.status.rawValue ?? "Draft")") { model.sendArrangerControl(control) }
                            }
                        }
                        Text("O app não assume estado on/off para toggles").font(.caption).foregroundStyle(.secondary)
                    }.padding(.leading, 42)
                }
            }.listStyle(.inset)
        }
    }
}

struct ExperimentRow: View {
    let number: Int; let title: String; let detail: String; let state: String; var action: (() -> Void)?; var secondary: (() -> Void)? = nil; var actionTitle: String?
    var body: some View {
        HStack(spacing: 14) {
            Text(String(number)).font(.headline).frame(width: 28, height: 28).background(.quaternary, in: Circle())
            VStack(alignment: .leading, spacing: 3) { HStack { Text(title).fontWeight(.semibold); Text(state).font(.caption.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 2).background((state == "Verified" ? LabTheme.verified : LabTheme.draft).opacity(0.16), in: Capsule()) }; Text(detail).foregroundStyle(.secondary) }
            Spacer()
            if let secondary { Button("Stop + Panic", action: secondary) }
            if let action, let actionTitle { Button(actionTitle, action: action) }
        }.padding(.vertical, 8)
    }
}
