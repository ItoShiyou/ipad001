import CoreGraphics
import Foundation

/// 1ページを描くのに必要な情報だけを写し取った値型。
///
/// SwiftData のモデルはメインアクタに束ねられていて他スレッドへ渡せないため、
/// 描画に渡す前にここへ写す。描画中にモデルが書き換わっても、
/// 描いている内容が途中で変わらないという保証にもなっている。
struct PageDescriptor: Sendable, Hashable {
    let scoreID: UUID
    /// 曲の中での通しページ番号。
    let pageIndex: Int
    let relativePath: String
    let kind: PageSource.Kind
    /// そのファイルの中での何ページ目か。
    let pageInSource: Int
    let cropRect: CGRect
    let rotation: Int
}

@MainActor
enum PageDescriptorFactory {
    /// 曲の指定ページから記述子を作る。範囲外なら nil。
    static func make(score: Score, pageIndex: Int) -> PageDescriptor? {
        guard let resolved = score.resolve(pageIndex: pageIndex) else { return nil }
        let setting = score.setting(forPage: pageIndex)
        return PageDescriptor(
            scoreID: score.id,
            pageIndex: pageIndex,
            relativePath: resolved.source.relativePath,
            kind: resolved.source.kind,
            pageInSource: resolved.pageInSource,
            cropRect: setting?.cropRect ?? CGRect(x: 0, y: 0, width: 1, height: 1),
            rotation: setting?.rotation ?? 0
        )
    }
}
