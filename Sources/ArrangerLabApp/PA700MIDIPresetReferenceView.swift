import SwiftUI

struct PA700MIDIPresetReferenceView: View {
    private struct PresetReference: Identifiable {
        let name: String
        let purpose: String?
        var id: String { name }
    }

    private let presets: [PresetReference] = [
        .init(name: "Default", purpose: nil),
        .init(name: "Master Kbd", purpose: nil),
        .init(name: "Player", purpose: nil),
        .init(name: "Accordion 1", purpose: nil),
        .init(name: "Accordion 2", purpose: nil),
        .init(name: "Accordion 3", purpose: nil),
        .init(name: "Tablet", purpose: "Seleção remota do SongBook e transmissão MIDI ao selecionar."),
        .init(name: "Key Control", purpose: "Roteamento documentado para Upper 3."),
        .init(name: "Mix Control", purpose: "Controles documentados de volume e pan."),
        .init(name: "Pad Control", purpose: "Upper 3 percussivo/especial e acordes do Arranger."),
        .init(name: "X/Y Control", purpose: "Dois parâmetros documentados de Upper 1."),
        .init(name: "Studio Ctrl", purpose: nil),
        .init(name: "Breath Ctrl", purpose: nil)
    ]

    var body: some View {
        DisclosureGroup("Referência: presets MIDI de fábrica") {
            VStack(alignment: .leading, spacing: 10) {
                Text("O manual descreve 16 slots substituíveis: 13 nomes foram identificados e 3 permanecem sem nome documentado.")
                    .foregroundStyle(.secondary)

                ForEach(presets) { preset in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(preset.name)
                            .fontWeight(.medium)
                            .frame(width: 110, alignment: .leading)
                        Text(preset.purpose ?? "Finalidade exata não inferida pela documentação analisada.")
                            .foregroundStyle(.secondary)
                    }
                }

                Label(
                    "Referência de configuração apenas; não cria nem valida mapeamentos CC, PC ou SysEx.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }
}
