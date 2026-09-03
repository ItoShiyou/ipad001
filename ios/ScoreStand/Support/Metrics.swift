import Foundation
import OSLog

/// 性能予算（NFR-01 / NFR-02）を計測するための signpost。
///
/// 「速いはず」で終わらせないために置いている。Instruments の
/// os_signpost 計器で、譜めくりの実測値をそのまま見る。
enum Metrics {
    /// Instruments の Points of Interest トラックに出すため、
    /// カテゴリを `.pointsOfInterest` にした `OSLog` を土台にする。
    static let signposter = OSSignposter(
        logHandle: OSLog(subsystem: "com.example.ScoreStand", category: .pointsOfInterest)
    )

    /// NFR-01: 操作から描画完了まで 16ms 以内。
    ///
    /// 呼び出し元（`PerformanceViewModel`）は入力を受けてから表示中のページが
    /// 実際に差し替わるまでの間、非同期に開始・終了する。1つのビューに対して
    /// 同時に進行するページめくりは高々1つなので、状態はここで一元管理する。
    ///
    /// 呼び出し元はすべて `@MainActor`（`PerformanceViewModel`）に限られるため
    /// 実際の競合は起きないが、`Metrics` 自体は `@MainActor` にしていない
    /// （`event(_:)` はバックグラウンドの描画タスクからも呼べるようにしたい）。
    /// そのため `nonisolated(unsafe)` で明示する。
    nonisolated(unsafe) private static var pageTurnState: OSSignpostIntervalState?

    static func beginPageTurn() {
        if let previous = pageTurnState {
            // 前回分が閉じられずに次が始まった（連打など）。計測が壊れるより
            // 未完了のまま閉じる方がまし。
            signposter.endInterval("pageTurn", previous)
        }
        pageTurnState = signposter.beginInterval("pageTurn")
    }

    static func endPageTurn() {
        guard let state = pageTurnState else { return }
        pageTurnState = nil
        signposter.endInterval("pageTurn", state)
    }

    /// NFR-02: コールドスタートから譜面表示まで 2.0 秒以内。
    ///
    /// アプリプロセスにつき一度しか意味を持たないため、pageTurn と同様に
    /// 状態をここで持つ。2回目以降の呼び出しは無視する。
    /// 呼び出し元はすべてメインスレッド（`ScoreStandApp.init` と
    /// `PerformanceViewModel`）。理由は `pageTurnState` と同じ。
    nonisolated(unsafe) private static var coldStartState: OSSignpostIntervalState?
    nonisolated(unsafe) private static var coldStartEnded = false

    static func beginColdStart() {
        coldStartState = signposter.beginInterval("coldStartToScore")
    }

    static func endColdStartIfNeeded() {
        guard !coldStartEnded, let state = coldStartState else { return }
        coldStartEnded = true
        signposter.endInterval("coldStartToScore", state)
    }

    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}
