import SwiftData
import SwiftUI

/// Folder rows shared by the library (top-level folders) and folder screens (subfolders).
/// Long-press a row to rename it, move it into another folder or delete it.
struct FolderRows: View {
    let folders: [Folder]
    @Environment(\.modelContext) private var context
    @Query private var allFolders: [Folder]
    @State private var naming: FolderNaming?
    @State private var folderToDelete: Folder?

    var body: some View {
        ForEach(folders) { folder in
            NavigationLink(value: folder) {
                row(folder)
            }
            .contextMenu {
                Button("Renomear", systemImage: "pencil") { naming = .rename(folder) }
                moveMenu(folder)
                Button("Apagar", systemImage: "trash", role: .destructive) { folderToDelete = folder }
            }
            .swipeActions {
                Button("Apagar", systemImage: "trash", role: .destructive) { folderToDelete = folder }
            }
        }
        .folderNamingAlert($naming)
        .confirmationDialog(
            "Apagar a pasta “\(folderToDelete?.name ?? "")”?",
            isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Apagar pasta", role: .destructive) {
                folderToDelete?.dissolve(in: context)
                try? context.save()
            }
        } message: {
            Text("As gravações e subpastas dela não serão apagadas. Elas vão para \(folderToDelete?.parent.map { "“\($0.name)”" } ?? "o início").")
        }
    }

    private func row(_ folder: Folder) -> some View {
        HStack {
            Label(folder.name, systemImage: folder.recordingKind == .meeting ? "person.2.fill" : "folder.fill")
            Spacer()
            if let language = folder.language {
                Label(language.displayName, systemImage: "globe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(folder.allLectures.count)")
                .foregroundStyle(.secondary)
        }
    }

    /// Every folder outside this one, by path, plus the top level.
    private func moveMenu(_ folder: Folder) -> some View {
        Menu("Mover para", systemImage: "folder") {
            Button("Início (sem pasta mãe)", systemImage: "house") { move(folder, into: nil) }
                .disabled(folder.parent == nil)
            ForEach(Folder.byPath(allFolders.filter { !folder.contains($0) })) { target in
                Button(target.path) { move(folder, into: target) }
                    .disabled(folder.parent == target)
            }
        }
    }

    private func move(_ folder: Folder, into parent: Folder?) {
        folder.parent = parent
        try? context.save()
    }
}

/// Creating a folder (at the top level or inside another) or renaming one.
enum FolderNaming: Identifiable {
    case create(parent: Folder?)
    case rename(Folder)

    var id: String {
        switch self {
        case .create(let parent): "create-\(parent?.id.uuidString ?? "root")"
        case .rename(let folder): "rename-\(folder.id.uuidString)"
        }
    }
}

extension View {
    func folderNamingAlert(_ naming: Binding<FolderNaming?>) -> some View {
        modifier(FolderNamingAlert(naming: naming))
    }
}

private struct FolderNamingAlert: ViewModifier {
    @Binding var naming: FolderNaming?
    @Environment(\.modelContext) private var context
    @State private var name = ""

    private var title: String {
        switch naming {
        case .rename: "Renomear pasta"
        case .create(let parent?): "Nova pasta em \(parent.name)"
        default: "Nova pasta"
        }
    }

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
                TextField("Disciplina ou projeto", text: $name)
                Button(isRenaming ? "Salvar" : "Criar", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancelar", role: .cancel) {}
            }
            .onChange(of: naming?.id) {
                if case .rename(let folder) = naming { name = folder.name } else { name = "" }
            }
    }

    private var isRenaming: Bool {
        if case .rename = naming { true } else { false }
    }

    private func save() {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        switch naming {
        case .rename(let folder): folder.name = name
        case .create(let parent): context.insert(Folder(name: name, parent: parent))
        case nil: return
        }
        try? context.save()
    }
}

extension Folder {
    /// Sorted by full path, so subfolders come right after their parent.
    static func byPath(_ folders: [Folder]) -> [Folder] {
        folders.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
