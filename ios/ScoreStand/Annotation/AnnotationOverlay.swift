import PencilKit
import SwiftData
import SwiftUI

/// 譜面の上に注釈レイヤを重ねる。
///
/// 譜面画像とは別のビューとして重ねているのは、**元のPDFを改変しない**という
/// 約束（FR-41 / 設計原則 P3）を、実装の構造そのもので保証するため。
/// 譜面側に書き込む経路が存在しなければ、書き込んでしまう事故も起こらない。
struct AnnotationOverlay: View {
    let score: Score
    let pageIndex: Int
    /// 編集中か。false のときは表示だけで、指や Pencil の入力を一切受けない。
    let isEditing: Bool
    let isVisible: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var drawing = PKDrawing()
    @State private var store: AnnotationStore?

    var body: some View {
        Group {
            if isVisible {
                AnnotationCanvasView(
                    drawing: $drawing,
                    isToolPickerVisible: isEditing,
                    isLayerVisible: true,
                    onDrawingChanged: { _ in
                        store?.saveDrawing(drawing, for: score, pageIndex: pageIndex)
                    }
                )
                // 編集していないときは入力を素通しする。
                // これをしないと、注釈を表示したまま譜めくりのタップが効かなくなる。
                .allowsHitTesting(isEditing)
            }
        }
        .onAppear { load() }
        .onChange(of: pageIndex) { _, _ in load() }
        .onChange(of: score.id) { _, _ in load() }
        .onDisappear { flush() }
    }

    private func load() {
        let store = store ?? AnnotationStore(context: modelContext)
        self.store = store
        drawing = store.loadDrawing(for: score, pageIndex: pageIndex)
    }

    /// ページを離れる瞬間に取りこぼしを防ぐ。
    /// 保存はデバウンスされているため、最後の一筆が未保存で残りうる。
    private func flush() {
        store?.saveDrawing(drawing, for: score, pageIndex: pageIndex)
    }
}
