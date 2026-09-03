import SwiftData
import SwiftUI

/// セットリスト一覧。作成・削除・複製・改名を行う（FR-30〜FR-33）。
struct SetlistListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Setlist.updatedAt, order: .reverse) private var setlists: [Setlist]

    @State private var pendingDeleteSetlist: Setlist?
    @State private var isDeleteConfirmPresented = false

    @State private var renamingSetlist: Setlist?
    @State private var renameText = ""

    @State private var errorMessage: String?
    @State private var isErrorPresented = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(setlists, id: \.id) { setlist in
                    NavigationLink {
                        SetlistEditorView(setlist: setlist)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(setlist.name)
                                .font(.headline)
                            Text("\(setlist.items.count)曲")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeleteSetlist = setlist
                            isDeleteConfirmPresented = true
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            duplicate(setlist)
                        } label: {
                            Label("複製", systemImage: "doc.on.doc")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            renamingSetlist = setlist
                            renameText = setlist.name
                        } label: {
                            Label("改名", systemImage: "pencil")
                        }
                        Button {
                            duplicate(setlist)
                        } label: {
                            Label("複製", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            pendingDeleteSetlist = setlist
                            isDeleteConfirmPresented = true
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("セットリスト")
            .overlay {
                if setlists.isEmpty {
                    ContentUnavailableView(
                        "セットリストがありません",
                        systemImage: "list.number",
                        description: Text("右上の＋から作成できます。")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        createSetlist()
                    } label: {
                        Label("追加", systemImage: "plus")
                    }
                }
            }
        }
        .confirmationDialog(
            "このセットリストを削除しますか？",
            isPresented: $isDeleteConfirmPresented,
            presenting: pendingDeleteSetlist
        ) { setlist in
            Button("「\(setlist.name)」を削除", role: .destructive) {
                delete(setlist)
            }
            Button("キャンセル", role: .cancel) {}
        } message: { _ in
            Text("セットリストの中身が削除されるだけで、曲そのものは残ります。この操作は元に戻せません。")
        }
        .alert("名前を変更", isPresented: renameBinding) {
            TextField("セットリスト名", text: $renameText)
            Button("変更") { commitRename() }
            Button("キャンセル", role: .cancel) { renamingSetlist = nil }
        }
        .alert("エラー", isPresented: $isErrorPresented, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renamingSetlist != nil }, set: { if !$0 { renamingSetlist = nil } })
    }

    private func createSetlist() {
        let setlist = Setlist(name: "新しいセットリスト")
        modelContext.insert(setlist)
        save()
    }

    private func duplicate(_ setlist: Setlist) {
        let copy = Setlist(name: setlist.name + " のコピー")
        modelContext.insert(copy)
        for item in setlist.orderedItems {
            guard let score = item.score else { continue }
            let newItem = copy.appending(score, note: item.note)
            modelContext.insert(newItem)
        }
        save()
    }

    private func delete(_ setlist: Setlist) {
        modelContext.delete(setlist)
        save()
    }

    private func commitRename() {
        guard let renamingSetlist else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            renamingSetlist.name = trimmed
            renamingSetlist.updatedAt = Date()
        }
        self.renamingSetlist = nil
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            isErrorPresented = true
        }
    }
}
