import SwiftData
import SwiftUI

/// 曲の各ページについて、余白の調整状態を一覧し編集する（FR-11 / FR-12）。
///
/// 一覧にプレビュー画像を並べないのは、500ページの楽譜で全ページを
/// 描画するとメモリと時間の両方を浪費するため。選んだ1ページだけを描く。
struct ScoreCropListView: View {
    let score: Score

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.displayScale) private var displayScale

    @State private var editingPageIndex: Int?
    @State private var preview: CGImage?
    @State private var isRendering = false

    var body: some View {
        List {
            Section {
                Text("スキャンした楽譜は余白が広く、そのままでは譜面が小さく表示される。切り詰めておくと暗い場所でも読みやすくなる。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(0..<score.pageCount, id: \.self) { pageIndex in
                Button {
                    open(pageIndex: pageIndex)
                } label: {
                    HStack {
                        Text("\(pageIndex + 1) ページ")
                        Spacer()
                        Text(statusText(for: pageIndex))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("余白の調整")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isRendering {
                ProgressView("ページを準備しています")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(isPresented: Binding(
            get: { editingPageIndex != nil && preview != nil },
            set: { if !$0 { editingPageIndex = nil; preview = nil } }
        )) {
            if let pageIndex = editingPageIndex {
                PageCropView(score: score, pageIndex: pageIndex, preview: preview) { rect in
                    save(cropRect: rect, pageIndex: pageIndex)
                }
            }
        }
    }

    private func statusText(for pageIndex: Int) -> String {
        guard let setting = score.setting(forPage: pageIndex), !setting.isDefault else {
            return "未調整"
        }
        return "調整済み"
    }

    /// 調整対象のページだけを、切り抜き前の状態で描いて渡す。
    ///
    /// 既存の切り抜きを適用して描くと、切り詰めた外側を戻せなくなる。
    /// ここでは常にページ全体を描く。
    private func open(pageIndex: Int) {
        guard let base = PageDescriptorFactory.make(score: score, pageIndex: pageIndex) else { return }
        let full = PageDescriptor(
            scoreID: base.scoreID,
            pageIndex: base.pageIndex,
            relativePath: base.relativePath,
            kind: base.kind,
            pageInSource: base.pageInSource,
            cropRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            rotation: base.rotation
        )
        let key = RenderKey(size: CGSize(width: 1200, height: 1600), scale: displayScale)

        isRendering = true
        Task {
            defer { isRendering = false }
            do {
                let page = try await environment.renderer.render(full, key: key)
                preview = page.image
                editingPageIndex = pageIndex
            } catch {
                Log.rendering.error("余白調整用のページ描画に失敗: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func save(cropRect: CGRect, pageIndex: Int) {
        if let existing = score.setting(forPage: pageIndex) {
            existing.cropRect = cropRect
        } else {
            let setting = PageSetting(pageIndex: pageIndex, cropRect: cropRect)
            setting.score = score
            score.pageSettings.append(setting)
            modelContext.insert(setting)
        }
        score.touch()
        try? modelContext.save()
    }
}
