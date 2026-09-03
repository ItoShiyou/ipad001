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
    static func pageTurn<T>(_ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval("pageTurn")
        defer { signposter.endInterval("pageTurn", state) }
        return try body()
    }

    /// NFR-02: コールドスタートから譜面表示まで 2.0 秒以内。
    static func beginColdStart() -> OSSignpostIntervalState {
        signposter.beginInterval("coldStartToScore")
    }

    static func endColdStart(_ state: OSSignpostIntervalState) {
        signposter.endInterval("coldStartToScore", state)
    }

    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}
