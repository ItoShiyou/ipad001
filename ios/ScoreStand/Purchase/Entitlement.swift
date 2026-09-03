import Foundation

/// 課金状態を表す。値そのものは PurchaseManager が保持し、
/// 判定ロジック（何曲まで登録できるか）はここに集約して各画面に条件分岐を散らばらせない。
enum Entitlement: Sendable, Equatable {
    case free
    case unlocked

    /// 無料枠の上限曲数。
    ///
    /// 競合の無料版は「曲の最初の1/4しか再生できない」という機能制限で
    /// 評価2.7に沈んだ。演奏中に機能が欠けると信頼できない楽器になってしまうため、
    /// このアプリは機能を削らず「曲数」だけを制限する設計にした。
    /// 3曲あれば購入前に実際の演奏で使い勝手を確認できる、という線引き。
    static let freeScoreLimit = 3

    /// 新しい楽譜を追加してよいかを判定する。
    /// 呼び出し側（各画面）はこの結果だけを見ればよく、上限値そのものを知る必要はない。
    func canAddScore(currentCount: Int) -> Bool {
        switch self {
        case .unlocked:
            return true
        case .free:
            return currentCount < Entitlement.freeScoreLimit
        }
    }
}
