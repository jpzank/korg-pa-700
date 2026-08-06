import ArrangerLabCore
import SwiftUI

struct ShowStyleBrowser: View {
    let styles: [ArrangerStyle]
    let selectedStyleID: String?
    let onSelect: (ArrangerStyle) -> Void
    @State private var searchText = ""
    @State private var library: String
    @State private var userBank: UInt8
    @State private var factoryCategory = "Todos"

    init(styles: [ArrangerStyle], selectedStyleID: String?, onSelect: @escaping (ArrangerStyle) -> Void) {
        self.styles = styles
        self.selectedStyleID = selectedStyleID
        self.onSelect = onSelect
        let selected = selectedStyleID.flatMap { id in styles.first { $0.id == id } }
        _library = State(initialValue: selected?.libraryName ?? "User")
        _userBank = State(initialValue: selected?.bankMSB == 2 ? selected?.bankLSB ?? 10 : 10)
    }

    private var factoryCategories: [String] {
        let values = Set(styles.filter { $0.libraryName == "Factory" }.map(\.category)).sorted()
        return ["Todos"] + values
    }

    private var userBanks: [(id: UInt8, name: String)] {
        ArrangerStyle.userBankNames
            .map { (id: $0.key, name: $0.value) }
            .sorted { $0.id < $1.id }
    }

    private var filteredStyles: [ArrangerStyle] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return styles.filter { style in
            let hierarchyMatches: Bool
            if library == "User" {
                hierarchyMatches = style.libraryName == "User" && style.bankLSB == userBank
            } else {
                hierarchyMatches = style.libraryName == "Factory"
                    && (factoryCategory == "Todos" || style.category == factoryCategory)
            }
            return hierarchyMatches
                && (query.isEmpty || style.displayName.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Selecionar Style")
                    .font(.title3.weight(.semibold))
                Text("Styles › Factory ou User › banco/categoria › Style › Keyboard Set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Biblioteca", selection: $library) {
                Text("Factory").tag("Factory")
                Text("User").tag("User")
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                TextField("Buscar Style", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                if library == "User" {
                    Picker("Banco User", selection: $userBank) {
                        ForEach(userBanks, id: \.id) { bank in
                            Text(bank.name).tag(bank.id)
                        }
                    }
                    .frame(width: 190)
                } else {
                    Picker("Categoria", selection: $factoryCategory) {
                        ForEach(factoryCategories, id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    .frame(width: 190)
                }
            }

            List(filteredStyles) { style in
                Button { onSelect(style) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(style.displayName)
                                .fontWeight(style.id == selectedStyleID ? .semibold : .regular)
                            Text(styleBreadcrumb(style))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if style.id == selectedStyleID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(LabTheme.verified)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }
            .listStyle(.inset)

            if filteredStyles.isEmpty {
                Text(library == "User"
                    ? "Nenhum Style deste banco foi catalogado ainda."
                    : "Nenhum Style encontrado nesta categoria.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(filteredStyles.count) Styles")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 680, height: 540)
    }

    private func styleBreadcrumb(_ style: ArrangerStyle) -> String {
        if let bank = style.userBankName {
            return "Styles › User › \(bank) › \(style.displayName) · \(style.address)"
        }
        return "Styles › Factory › \(style.category) › \(style.displayName) · \(style.address)"
    }
}
