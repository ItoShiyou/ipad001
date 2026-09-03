import SwiftData
import SwiftUI

/// セットリストの編集画面。曲の追加・並べ替え・削除・メモ編集を行う（FR-30〜FR-33）。
struct SetlistEditorView: View {
    @Bindable var setlist: Setlist

    @Environment(\.modelContext) private var modelContext
    @State private var isAddScorePresented = false
    @State private var isPerformancePresented = false

    @State private var errorMessage: String?
    @State private var isErrorPresented = false

    var body: some View {
        List {
            Section {
                TextField("セットリスト名", text: $setlist.name)
                    .font(.headline)
                    .onSubmit { setlist.updatedAt = Date(); save() }
            }

            Section {
                Button {
                    isPerformancePresented = true
                } label: {
                    Label("演奏を開始", systemImage: "play.fill")
                }
                .disabled(setlist.orderedItems.isEmpty)
            }

            Section("曲順") {
                ForEach(setlist.orderedItems, id: \.id) { item in
                    setlistItemRow(item)
                }
                .onMove(perform: moveItems)
                .onDelete(perform: deleteItems)

                if setlist.orderedItems.isEmpty {
                    Text("まだ曲がありません。右下の＋から追加してください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(setlist.name.isEmpty ? "セットリスト" : setlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isAddScorePresented = true
                } label: {
                    Label("曲を追加", systemImage: "plus")
                }
            }
            // FR-34（ベータ・C優先度）。テキストのみの書き出し。
            // PDF化まではまだ対応していない。
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: exportText) {
                    Label("書き出し（ベータ）", systemImage: "square.and.arrow.up")
                }
                .disabled(setlist.orderedItems.isEmpty)
            }
        }
        .sheet(isPresented: $isAddScorePresented) {
            AddScoreToSetlistView(setlist: setlist) { save() }
        }
        .fullScreenCover(isPresented: $isPerformancePresented) {
            PerformanceLauncherView(context: .setlist(setlist, index: 0))
        }
        .alert("エラー", isPresented: $isErrorPresented, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    /// FR-34（ベータ）: セットリストをテキストとして書き出す。
    /// 曲順・曲名・作曲者・メモを1行ずつ並べるだけの単純な形式にしている。
    private var exportText: String {
        var lines = ["\(setlist.name.isEmpty ? "セットリスト" : setlist.name)", ""]
        for (index, item) in setlist.orderedItems.enumerated() {
            var line = "\(index + 1). \(item.score?.title ?? "（削除された曲）")"
            if let composer = item.score?.composer, !composer.isEmpty {
                line += "（\(composer)）"
            }
            lines.append(line)
            if !item.note.isEmpty {
                lines.append("   \(item.note)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func setlistItemRow(_ item: SetlistItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.score?.title ?? "（削除された曲）")
                .font(.body)
            TextField("メモ（キー・テンポ・MCなど）", text: noteBinding(for: item))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func noteBinding(for item: SetlistItem) -> Binding<String> {
        Binding(
            get: { item.note },
            set: { item.note = $0 }
        )
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var items = setlist.orderedItems
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            item.order = index
        }
        setlist.updatedAt = Date()
        save()
    }

    private func deleteItems(at offsets: IndexSet) {
        let items = setlist.orderedItems
        for index in offsets {
            let item = items[index]
            setlist.items.removeAll { $0.id == item.id }
            modelContext.delete(item)
        }
        setlist.renumber()
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

/// セットリストへ追加する曲を選ぶシート。
private struct AddScoreToSetlistView: View {
    let setlist: Setlist
    let onAdded: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Score.title) private var scores: [Score]
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredScores, id: \.id) { score in
                    Button {
                        add(score)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(score.title)
                                if !score.composer.isEmpty {
                                    Text(score.composer)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if isAlreadyIncluded(score) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .searchable(text: $searchText, prompt: "曲名で検索")
            .navigationTitle("曲を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var filteredScores: [Score] {
        guard !searchText.isEmpty else { return scores }
        return scores.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private func isAlreadyIncluded(_ score: Score) -> Bool {
        setlist.items.contains { $0.score?.id == score.id }
    }

    private func add(_ score: Score) {
        let item = setlist.appending(score)
        modelContext.insert(item)
        onAdded()
    }
}
