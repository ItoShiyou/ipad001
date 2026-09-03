import Foundation

/// 譜めくり操作の種類。入力方式が何であれ、最終的にこれに変換される。
enum PageTurnCommand: Equatable, Sendable {
    case next
    case previous
    /// セットリスト上の次の曲・前の曲へ。
    case nextScore
    case previousScore
    /// 通しページ番号への直接移動（ジャンプ先、ブックマーク）。
    case jump(pageIndex: Int)
}

/// どの入力方式から来たか。
///
/// 表示（FR-86: 今どの入力が生きているか）と、
/// 将来の調停（同時発火時にどれを優先するか）のために保持する。
enum InputSourceKind: String, Sendable, CaseIterable {
    case tap
    case keyboard        // HIDキーボード（フットスイッチ、Bluetoothリモコン）
    case midi            // FR-27（v1では未実装）
    case remoteDevice    // iPhone / Apple Watch（v1.x）
    case camera          // 顔・視線（保留）
    case timeline        // 記録タイミングの再生（v1.5）

    /// 人間の直接操作か。
    ///
    /// 設計原則 P6「自動化は提案しかできない。人間の操作が常に勝つ」の判定に使う。
    /// 自動系（timeline / camera）は、手動入力が来た時点で自分を明け渡す。
    var isManual: Bool {
        switch self {
        case .tap, .keyboard, .midi, .remoteDevice:
            return true
        case .camera, .timeline:
            return false
        }
    }
}

struct PageTurnEvent: Sendable {
    let command: PageTurnCommand
    let source: InputSourceKind
    let timestamp: Date

    init(_ command: PageTurnCommand, from source: InputSourceKind, at timestamp: Date = Date()) {
        self.command = command
        self.source = source
        self.timestamp = timestamp
    }
}

/// 譜めくりイベントを発生させるものの共通形。
///
/// 方式を後から差し替えても演奏ビューに手を入れずに済むよう、
/// 入力側はすべてこの形に揃える（docs/page-turn-input.md の統一入力層）。
@MainActor
protocol PageTurnInputSource: AnyObject {
    var kind: InputSourceKind { get }
    var isActive: Bool { get }
    var handler: ((PageTurnEvent) -> Void)? { get set }

    func activate()
    func deactivate()
}
