import Foundation
import UIKit

/// 演奏中であることを、アプリ全体に知らせる。
///
/// NFR-05 の実装点。演奏中は取り込み・サムネイル生成・索引作成といった
/// 後回しにできる仕事を**すべて止める**。譜めくりの1フレームは、
/// どの機能よりも重い（設計原則 P1）。
@MainActor
@Observable
final class PerformanceSession {
    private(set) var isPerforming = false

    /// 演奏中に走らせてよい仕事かを、各所がこれで判定する。
    var allowsBackgroundWork: Bool { !isPerforming }

    /// 誤操作防止ロック（FR-25）。譜めくり以外の操作を止める。
    var isLocked = false

    private var deferredWork: [() -> Void] = []

    func begin() {
        guard !isPerforming else { return }
        isPerforming = true
        // 演奏中に画面が消えるのは事故に直結する（NFR-06）。
        UIApplication.shared.isIdleTimerDisabled = true
        Metrics.event("performanceBegin")
        Log.performance.info("演奏モード開始")
    }

    func end() {
        guard isPerforming else { return }
        isPerforming = false
        isLocked = false
        UIApplication.shared.isIdleTimerDisabled = false
        Log.performance.info("演奏モード終了")
        flushDeferredWork()
    }

    /// 演奏中なら後回しにし、そうでなければ即座に実行する。
    ///
    /// 呼び出し側が毎回 `isPerforming` を見て分岐すると必ず抜けが出るので、
    /// 「後回しにできる仕事はこれを通す」という一本道にしている。
    func perform(deferrable work: @escaping () -> Void) {
        if isPerforming {
            deferredWork.append(work)
        } else {
            work()
        }
    }

    private func flushDeferredWork() {
        let work = deferredWork
        deferredWork.removeAll()
        for item in work {
            item()
        }
        if !work.isEmpty {
            Log.performance.info("保留していた処理を \(work.count) 件実行")
        }
    }
}
