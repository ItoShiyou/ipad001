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
    /// 譜面が反転表示（FR-13）のときは、注釈も一緒に反転する。
    ///
    /// 譜面だけ白黒反転して注釈の色はそのままだと、暗所で書き込みが
    /// 埋もれて見えなくなる（実機で判明）。書き込んだ本人の意図した色が
    /// 変わって見えるが、暗所での可読性を優先する。
    var isInverted: Bool = false

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
                    onDrawingChanged: { [score, pageIndex] data in
                        // `@State var drawing` を読まず、渡された `data` をそのまま使う。
                        // `drawing` は生きた共有ストレージなので、デバウンス発火が
                        // ページ送りの後にずれ込むと別ページの内容を読んでしまう。
                        // `score` / `pageIndex` もこの時点の値に固定して閉じ込める。
                        guard let drawing = try? PKDrawing(data: data) else { return }
                        store?.saveDrawing(drawing, for: score, pageIndex: pageIndex)
                    }
                )
                // 編集していないときは入力を素通しする。
                // これをしないと、注釈を表示したまま譜めくりのタップが効かなくなる。
                .allowsHitTesting(isEditing)
                .colorInvert(isEnabled: isInverted)
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
