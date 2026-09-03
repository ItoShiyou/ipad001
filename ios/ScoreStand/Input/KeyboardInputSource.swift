import Foundation
import UIKit

/// ハードウェアキーボードとして接続される機器からの譜めくり（FR-21 / FR-22 / FR-28）。
///
/// AirTurn や PageFlip などの譜めくりペダル、および汎用の Bluetooth リモコンは、
/// いずれも **BLE HID キーボードとして振る舞う**。したがって BLE を自前で扱う必要はなく、
/// キー入力として受ければ機種を問わず動く。ここが「安く広く効く」入力方式である理由。
@MainActor
final class KeyboardInputSource: PageTurnInputSource {
    let kind: InputSourceKind = .keyboard
    private(set) var isActive = false
    var handler: ((PageTurnEvent) -> Void)?

    /// 機器ごとに送出するキーが違うため、割り当てを差し替えられるようにしておく。
    /// 主要機種を初期値で網羅しつつ、想定外の機種はユーザーが設定で足せる（FR-21 の但し書き）。
    var forwardKeys: Set<String>
    var backwardKeys: Set<String>

    init() {
        // AirTurn 既定 (上/下)、PageFlip 既定 (右/左)、汎用リモコン (スペース、Page Down 相当)
        forwardKeys = [
            UIKeyCommand.inputRightArrow,
            UIKeyCommand.inputDownArrow,
            UIKeyCommand.inputPageDown,
            " "
        ]
        backwardKeys = [
            UIKeyCommand.inputLeftArrow,
            UIKeyCommand.inputUpArrow,
            UIKeyCommand.inputPageUp
        ]
    }

    func activate() { isActive = true }
    func deactivate() { isActive = false }

    /// 受け取ったキーを譜めくりに変換する。処理したら true を返す。
    func handleKey(_ input: String) -> Bool {
        guard isActive else { return false }
        if forwardKeys.contains(input) {
            handler?(PageTurnEvent(.next, from: .keyboard))
            return true
        }
        if backwardKeys.contains(input) {
            handler?(PageTurnEvent(.previous, from: .keyboard))
            return true
        }
        return false
    }

    /// SwiftUI に渡すためのキー一覧。
    var allKeys: [String] {
        Array(forwardKeys.union(backwardKeys))
    }
}
