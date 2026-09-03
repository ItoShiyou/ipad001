import Foundation
import StoreKit

/// 購入フローの進行状態。
enum PurchaseState: Equatable {
    case idle
    case purchasing
    case restoring
    case failed(String)
}

/// ユーザーに提示するための購入エラー。
enum PurchaseError: LocalizedError {
    case productNotFound
    case verificationFailed
    case pending
    case unknown

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "購入項目を取得できませんでした。しばらくしてから再度お試しください。"
        case .verificationFailed:
            return "購入情報を確認できませんでした。時間をおいて再度お試しください。"
        case .pending:
            return "購入の承認待ちです。承認が完了すると自動的に反映されます。"
        case .unknown:
            return "購入処理に失敗しました。時間をおいて再度お試しください。"
        }
    }
}

/// StoreKit 2 を用いた非消費型IAP（曲数無制限化）の購入管理。
///
/// このアプリはネットワーク権限を持たないが、StoreKit のサーバー通信はOS側の
/// StoreKitフレームワークが（アプリのネットワーク権限とは独立に）行うため契約に反しない。
@MainActor
@Observable
final class PurchaseManager {

    /// 非消費型IAPのプロダクトID（Universal Purchase：iPhone/iPadで共通の1件）。
    static let unlockProductID = "com.example.ScoreStand.unlock"

    /// 起動時にまず参照するローカルの購入済みフラグのキー。
    ///
    /// `Transaction.currentEntitlements` は端末がオフラインだとStoreKitの
    /// ローカルレシート検証に頼ることになり、環境によっては即座に結果を返せないことがある。
    /// ライブ会場の圏外で「購入したのにロックされる」事故を避けるため、
    /// 購入確定時にこのフラグをミラーしておき、起動直後は StoreKit の応答を待たず
    /// まずこのフラグで解放状態を決める。その後 currentEntitlements / Transaction.updates で
    /// 答え合わせをして、必要ならフラグを更新する（失効・返金の反映）。
    private static let unlockedDefaultsKey = "com.example.ScoreStand.purchase.unlocked"

    private(set) var isUnlocked: Bool
    private(set) var product: Product?
    private(set) var purchaseState: PurchaseState = .idle

    /// 監視タスクの入れ物。
    ///
    /// `deinit` は nonisolated なので、メインアクタに束縛された保存プロパティを
    /// 直接触れない。取り消しだけを担う小さな箱に逃がし、箱自身の `deinit` で
    /// 片付ける。書き込みは `init` の一度きりなので、境界を跨いだ競合は起きない。
    private final class UpdatesTaskHolder: @unchecked Sendable {
        var task: Task<Void, Never>?
        deinit { task?.cancel() }
    }

    private let updates = UpdatesTaskHolder()

    init() {
        // オフライン起動でも即座に解放状態を確定させるため、まずローカルフラグを読む。
        self.isUnlocked = UserDefaults.standard.bool(forKey: Self.unlockedDefaultsKey)
        // アプリ生存期間中、返金・失効・他端末での購入を継続的に反映する。
        updates.task = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(updateResult: update)
            }
        }
    }

    /// ストアからプロダクト情報を取得する。表示前に呼ぶ。
    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.unlockProductID])
            self.product = products.first
        } catch {
            Log.purchase.error("プロダクト取得に失敗: \(error.localizedDescription)")
        }
    }

    /// 現在の所有状況を StoreKit に問い合わせて反映する。
    /// オフライン時は応答が得られないことがあるため、失敗してもローカルフラグ（isUnlocked）は変更しない。
    func refreshEntitlements() async {
        var foundUnlock = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.unlockProductID {
                foundUnlock = true
            }
        }
        if foundUnlock {
            setUnlocked(true)
        }
        // ここで false のまま上書きしないのは、オフライン等で currentEntitlements が
        // 一時的に空を返した場合に「購入済みなのにロックされる」事故を防ぐため。
        // 失効・返金は Transaction.updates 側の revocationDate で個別に反映する。
    }

    /// 購入を開始する。
    func purchase() async {
        guard let product else {
            purchaseState = .failed(PurchaseError.productNotFound.localizedDescription)
            return
        }
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    setUnlocked(true)
                    await transaction.finish()
                    purchaseState = .idle
                case .unverified:
                    purchaseState = .failed(PurchaseError.verificationFailed.localizedDescription)
                }
            case .userCancelled:
                // キャンセルはユーザーの意思なのでエラー表示はしない。
                purchaseState = .idle
            case .pending:
                purchaseState = .failed(PurchaseError.pending.localizedDescription)
            @unknown default:
                purchaseState = .failed(PurchaseError.unknown.localizedDescription)
            }
        } catch {
            purchaseState = .failed(PurchaseError.unknown.localizedDescription)
            Log.purchase.error("購入処理に失敗: \(error.localizedDescription)")
        }
    }

    /// 購入の復元。機種変更・再インストール後などに使用する。
    func restore() async {
        purchaseState = .restoring
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            purchaseState = .idle
        } catch {
            // 復元に失敗してもローカルにフラグが残っていれば isUnlocked はそのまま解放状態を維持する。
            purchaseState = .failed(PurchaseError.unknown.localizedDescription)
            Log.purchase.error("購入復元に失敗: \(error.localizedDescription)")
        }
    }

    /// 曲を追加してよいかを判定する。判定ロジック自体は Entitlement 側に集約する。
    func canAddScore(currentCount: Int) -> Bool {
        let entitlement: Entitlement = isUnlocked ? .unlocked : .free
        return entitlement.canAddScore(currentCount: currentCount)
    }

    private func handle(updateResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = updateResult, transaction.productID == Self.unlockProductID else {
            return
        }
        if transaction.revocationDate != nil {
            // 返金などで取り消された場合のみロック状態に戻す。
            setUnlocked(false)
        } else {
            setUnlocked(true)
        }
        await transaction.finish()
    }

    private func setUnlocked(_ value: Bool) {
        isUnlocked = value
        UserDefaults.standard.set(value, forKey: Self.unlockedDefaultsKey)
    }
}
