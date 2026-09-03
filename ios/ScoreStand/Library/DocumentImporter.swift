import Foundation
import PDFKit
import SwiftData
import UniformTypeIdentifiers

/// 外部のPDF・画像を取り込んで `Score` を作る。
@MainActor
final class DocumentImporter {
    static let supportedTypes: [UTType] = [.pdf, .image]

    private let store: ScoreStore
    private let context: ModelContext

    init(store: ScoreStore, context: ModelContext) {
        self.store = store
        self.context = context
    }

    /// 複数ファイルを1曲として取り込む（FR-06 の連結にあたる）。
    ///
    /// 曲名を渡さなければ最初のファイル名から作る。楽譜は
    /// 「ファイル名＝曲名」であることが多いので、初期値として妥当なため。
    @discardableResult
    func importScore(from urls: [URL], title: String? = nil) throws -> Score {
        guard !urls.isEmpty else { throw ImportError.noFiles }

        let resolvedTitle = title ?? urls[0].deletingPathExtension().lastPathComponent
        let score = Score(title: resolvedTitle)
        context.insert(score)

        var order = 0
        var importedPaths: [String] = []

        do {
            for url in urls {
                let source = try makeSource(from: url, order: order)
                source.score = score
                score.sources.append(source)
                importedPaths.append(source.relativePath)
                order += 1
            }
        } catch {
            // 途中で失敗したら、それまでにコピーした実体を残さない。
            // 孤立ファイルはユーザーからは見えず、容量だけを食い続けるため。
            importedPaths.forEach { store.delete(relativePath: $0) }
            context.delete(score)
            throw error
        }

        guard score.pageCount > 0 else {
            importedPaths.forEach { store.delete(relativePath: $0) }
            context.delete(score)
            throw ImportError.emptyDocument
        }

        try context.save()
        Log.library.info("取り込み完了: \(resolvedTitle, privacy: .public) \(score.pageCount)ページ")
        return score
    }

    /// 既存の曲に追記する。
    @discardableResult
    func appendSources(to score: Score, from urls: [URL]) throws -> Int {
        var order = (score.sources.map(\.order).max() ?? -1) + 1
        var added = 0
        for url in urls {
            let source = try makeSource(from: url, order: order)
            source.score = score
            score.sources.append(source)
            order += 1
            added += 1
        }
        score.touch()
        try context.save()
        return added
    }

    /// 曲を削除し、参照されなくなった実体も片付ける。
    func delete(_ score: Score) throws {
        let paths = score.sources.map(\.relativePath)
        context.delete(score)
        try context.save()
        paths.forEach { store.delete(relativePath: $0) }
    }

    private func makeSource(from url: URL, order: Int) throws -> PageSource {
        let ext = url.pathExtension.lowercased()
        let kind: PageSource.Kind = (ext == "pdf") ? .pdf : .image

        let relativePath = try store.importFile(at: url)
        let pageCount: Int

        switch kind {
        case .pdf:
            guard let document = PDFDocument(url: store.fileURL(for: relativePath)) else {
                store.delete(relativePath: relativePath)
                throw ImportError.unreadable(url.lastPathComponent)
            }
            // 暗号化されたPDFは開けても描画できないことがある。取り込み時点で弾く方が、
            // 本番でページが真っ白になるより遥かにましである。
            if document.isEncrypted && document.isLocked {
                store.delete(relativePath: relativePath)
                throw ImportError.locked(url.lastPathComponent)
            }
            pageCount = document.pageCount
        case .image:
            pageCount = 1
        }

        return PageSource(
            relativePath: relativePath,
            kind: kind,
            pageCount: pageCount,
            order: order,
            originalName: url.lastPathComponent
        )
    }
}

enum ImportError: LocalizedError {
    case noFiles
    case emptyDocument
    case unreadable(String)
    case locked(String)

    var errorDescription: String? {
        switch self {
        case .noFiles:
            return "取り込むファイルが選ばれていません。"
        case .emptyDocument:
            return "ページのないファイルは取り込めません。"
        case .unreadable(let name):
            return "「\(name)」を読み込めませんでした。ファイルが壊れている可能性があります。"
        case .locked(let name):
            return "「\(name)」はパスワードで保護されているため取り込めません。"
        }
    }
}
