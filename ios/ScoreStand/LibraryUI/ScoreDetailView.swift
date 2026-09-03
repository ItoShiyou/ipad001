import SwiftData
import SwiftUI

/// 曲の詳細・メタデータ編集画面。
struct ScoreDetailView: View {
    @Bindable var score: Score

    @Environment(\.modelContext) private var modelContext
    @State private var tagsText: String = ""
    @State private var isPerformancePresented = false

    var body: some View {
        Form {
            Section("演奏") {
                Button {
                    isPerformancePresented = true
                } label: {
                    Label("演奏を開始", systemImage: "play.fill")
                }
                .disabled(score.pageCount == 0)
            }

            Section("メタデータ") {
                TextField("タイトル", text: $score.title)
                TextField("作曲者", text: $score.composer)
                TextField("編成", text: $score.ensemble)
                TextField("タグ（カンマ区切り）", text: $tagsText)
                    .onChange(of: tagsText) { _, newValue in
                        score.tags = newValue
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
            }

            Section("情報") {
                LabeledContent("ページ数", value: "\(score.pageCount)")
                ForEach(score.sources.sorted(by: { $0.order < $1.order }), id: \.id) { source in
                    LabeledContent(source.originalName, value: "\(source.pageCount)ページ")
                }
            }
        }
        .navigationTitle(score.title.isEmpty ? "無題の楽譜" : score.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            tagsText = score.tags.joined(separator: ", ")
        }
        .onDisappear {
            // 演奏中の負荷を避けたいのでここでは deferrable にはしない
            // （詳細画面を閉じる時点では演奏は始まっていないため）。
            score.touch()
            try? modelContext.save()
        }
        .fullScreenCover(isPresented: $isPerformancePresented) {
            PerformanceLauncherView(context: .single(score))
        }
    }
}
