import Foundation

/// 画面のタップによる譜めくり（FR-20 / FR-29b）。
///
/// **すべての入力方式の土台。** ペダルもMIDIもリモートも持たない奏者が、
/// 何も買わずに必ず使える唯一の手段なので、これだけは常に有効にしておく。
@MainActor
final class TapInputSource: PageTurnInputSource {
    let kind: InputSourceKind = .tap
    private(set) var isActive = false
    var handler: ((PageTurnEvent) -> Void)?

    func activate() { isActive = true }
    func deactivate() { isActive = false }

    /// 画面上の位置から、進む・戻るを決める。
    ///
    /// 判定領域を画面幅の 1/3 と広く取っているのは、演奏中に手元を見ずに、
    /// 前腕や小指で触れてもめくれるようにするため（FR-29b）。
    /// 中央を無反応にしているのは、譜面を確認しようとして触れた指で
    /// めくってしまう事故を防ぐため。
    func handleTap(at x: CGFloat, width: CGFloat) {
        guard isActive, width > 0 else { return }
        let ratio = x / width
        if ratio < 0.33 {
            handler?(PageTurnEvent(.previous, from: .tap))
        } else if ratio > 0.67 {
            handler?(PageTurnEvent(.next, from: .tap))
        }
    }

    func handleSwipe(isForward: Bool) {
        guard isActive else { return }
        handler?(PageTurnEvent(isForward ? .next : .previous, from: .tap))
    }
}
