import SwiftData
import SwiftUI

/// 曲の詳細・メタデータ編集画面。
struct ScoreDetailView: View {
    @Bindable var score: Score

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var environment
    @State private var tagsText: String = ""
    @State private var isPerformancePresented = false
    @State private var isPracticeToolsPresented = false
    @State private var isAppendImporterPresented = false
    @State private var errorMessage: String?
    @State private var isErrorPresented = false

    var body: some View {
        Form {
            Section("演奏") {
                Button {
                    isPerformancePresented = true
                } label: {
                    Label("演奏を開始", systemImage: "play.fill")
                }
                .disabled(score.pageCount == 0)

                Button {
                    isPracticeToolsPresented = true
                } label: {
                    Label("練習ツール（メトロノーム・チューナー）", systemImage: "metronome")
                }
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

            Section("表示") {
                NavigationLink {
                    ScoreCropListView(score: score)
                } label: {
                    Label("余白の調整", systemImage: "crop")
                }
                .disabled(score.pageCount == 0)
            }

            jumpPointsSection

            Section {
                LabeledContent("ページ数", value: "\(score.pageCount)")
                ForEach(score.sources.sorted(by: { $0.order < $1.order }), id: \.id) { source in
                    LabeledContent(source.originalName, value: "\(source.pageCount)ページ")
                }
                Button {
                    isAppendImporterPresented = true
                } label: {
                    Label("PDF / 画像を追記", systemImage: "doc.badge.plus")
                }
            } header: {
                Text("情報")
            } footer: {
                // FR-06: 複数PDFを1曲として連結する（の「後から追記する」側）。
                Text("追記したファイルは既存ページの後ろに追加されます。")
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
        .sheet(isPresented: $isPracticeToolsPresented) {
            PracticeToolsView(score: score)
        }
        .fileImporter(
            isPresented: $isAppendImporterPresented,
            allowedContentTypes: DocumentImporter.supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            handleAppendResult(result)
        }
        .alert("エラー", isPresented: $isErrorPresented, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    private func handleAppendResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            do {
                try environment.makeImporter().appendSources(to: score, from: urls)
            } catch {
                errorMessage = error.localizedDescription
                isErrorPresented = true
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            isErrorPresented = true
        }
    }

    /// FR-26（ベータ）: リピート / D.S. / Coda などのジャンプ先を登録する。
    private var jumpPointsSection: some View {
        Section {
            ForEach(score.jumpPoints.sorted(by: { $0.order < $1.order }), id: \.id) { point in
                HStack {
                    TextField("ラベル（D.S. / Coda など）", text: labelBinding(for: point))
                    Spacer()
                    Stepper(value: pageIndexBinding(for: point), in: 0...max(0, score.pageCount - 1)) {
                        Text("\(point.pageIndex + 1)ページ目")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }
            }
            .onDelete(perform: deleteJumpPoints)

            Button {
                addJumpPoint()
            } label: {
                Label("ジャンプ先を追加", systemImage: "plus")
            }
            .disabled(score.pageCount == 0)
        } header: {
            Text("ジャンプ先（ベータ）")
        } footer: {
            Text("演奏中に1操作で飛べます。リピート・D.S.・Coda などの登録に使ってください。")
        }
    }

    private func labelBinding(for point: JumpPoint) -> Binding<String> {
        Binding(get: { point.label }, set: { point.label = $0 })
    }

    private func pageIndexBinding(for point: JumpPoint) -> Binding<Int> {
        Binding(get: { point.pageIndex }, set: { point.pageIndex = $0 })
    }

    private func addJumpPoint() {
        let point = JumpPoint(label: "新しいジャンプ先", pageIndex: 0, order: score.jumpPoints.count)
        point.score = score
        score.jumpPoints.append(point)
        modelContext.insert(point)
    }

    private func deleteJumpPoints(at offsets: IndexSet) {
        let points = score.jumpPoints.sorted(by: { $0.order < $1.order })
        for index in offsets {
            let point = points[index]
            score.jumpPoints.removeAll { $0.id == point.id }
            modelContext.delete(point)
        }
    }
}
