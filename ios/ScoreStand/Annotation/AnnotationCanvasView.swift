import SwiftUI
import PencilKit

/// 譜面画像の上に重ねて使う手書き注釈レイヤー。
/// PKCanvasView を SwiftUI から扱うための薄いラッパー。
struct AnnotationCanvasView: UIViewRepresentable {
    /// 表示するストローク一式。外部（AnnotationStore）から読み込んだものを流し込む。
    @Binding var drawing: PKDrawing
    /// ツールパレット（色/太さ/消しゴム選択 UI）を出すかどうか。
    var isToolPickerVisible: Bool
    /// 注釈レイヤー自体の表示/非表示（FR-42）。非表示時は描画は保持したまま見た目だけ消す。
    var isLayerVisible: Bool
    /// 描画がまとまった（デバウンス後）タイミングで呼ばれる保存コールバック。
    var onDrawingChanged: (Data) -> Void

    /// 指で楽譜をめくろうとした/触れただけで線が引かれる事故を防ぐため、
    /// 既定は Apple Pencil のみを許可する。指描画が必要な場合は呼び出し側で
    /// `.anyInput` を選べるように差し替え可能にしておく。
    var drawingPolicy: PKCanvasViewDrawingPolicy = .pencilOnly

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        canvas.drawingPolicy = drawingPolicy
        // 背景を透明にして、下にある譜面画像がそのまま透けて見えるようにする。
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        canvas.isHidden = !isLayerVisible
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // Coordinator が保持する parent（＝ onDrawingChanged クロージャ）を、
        // 毎回の再構成で必ず最新に差し替える。ここを怠ると保存先のページが
        // 固定されたままになる（Coordinator 側のコメント参照）。
        context.coordinator.parent = self
        // 外部から drawing が更新された場合のみ反映する（無限ループ防止）。
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
        canvas.drawingPolicy = drawingPolicy
        canvas.isHidden = !isLayerVisible

        // PKToolPicker.shared(for:) は iOS 16 で非推奨になった。
        // Coordinator に1つ持たせて、このキャンバス専用のものとして扱う。
        let picker = context.coordinator.toolPicker
        picker.setVisible(isToolPickerVisible, forFirstResponder: canvas)
        if isToolPickerVisible {
            picker.addObserver(canvas)
            canvas.becomeFirstResponder()
        } else {
            picker.removeObserver(canvas)
            canvas.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        /// このキャンバス専用のツールピッカー。共有インスタンスに頼らないことで、
        /// 複数のキャンバスが同時に存在しても状態が混ざらない。
        let toolPicker = PKToolPicker()
        /// `updateUIView` のたびに書き換える。`let` のままにして初回の値に
        /// 固定してしまうと、ページが変わっても `onDrawingChanged` が
        /// 最初のページ用のクロージャのままになり、以降の保存先がずっと
        /// 最初のページに固定される事故になる。
        var parent: AnnotationCanvasView
        // 1ストロークごとに保存すると I/O が頻発して重くなるため、
        // 描画がしばらく止まったタイミングでまとめて1回だけ通知する（デバウンス）。
        private var debounceWorkItem: DispatchWorkItem?
        private let debounceInterval: TimeInterval = 0.6

        init(_ parent: AnnotationCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let drawing = canvasView.drawing
            parent.drawing = drawing

            // 保存先のクロージャは「今ストロークが起きた瞬間」の parent から取り出して
            // 固定する。デバウンス発火時（0.6秒後）に self.parent を読み直すと、
            // その間にページがめくられていた場合、正しいページの描画データを
            // 別の（めくった後の）ページへ保存してしまう。
            let callback = parent.onDrawingChanged

            debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                callback(drawing.dataRepresentation())
            }
            debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
        }
    }
}
