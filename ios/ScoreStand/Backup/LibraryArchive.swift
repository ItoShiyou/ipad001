import CoreGraphics
import Foundation
import SwiftData

/// ライブラリ全体の書き出し / 読み込み（FR-60）。
///
/// 書き出し先はユーザー自身の iCloud Drive / Files を想定する（FR-61）。
/// このアプリはネットワーク権限を持たず、自前サーバーには一切送らない。
/// フォーマットは `ArchiveFormat.swift` に定義した単純な自前コンテナで、
/// 仕様を公開すればユーザーが将来他アプリへ移れる（FR-62）。
@MainActor
final class LibraryArchive {
    private let store: ScoreStore
    private let modelContext: ModelContext

    init(store: ScoreStore, modelContext: ModelContext) {
        self.store = store
        self.modelContext = modelContext
    }

    // MARK: - 書き出し

    /// 指定した曲・セットリストを1ファイルにまとめて書き出す。
    ///
    /// `url` はユーザーが Files / iCloud Drive で選んだ書き出し先（`.scorestand`）。
    /// ドキュメントピッカー経由の URL はセキュリティスコープ付きのことがあるため、
    /// アクセス開始・終了を必ず対にする。
    ///
    /// `async` なのは、書き出しの実体がファイル I/O だからである。数GBのPDFを
    /// メインアクタで書くと画面が固まり、ウォッチドッグに落とされる。
    /// モデルから値型へ写し終えた時点で、以降はメインスレッドの外へ出す。
    func export(
        scores: [Score],
        setlists: [Setlist],
        to url: URL,
        progress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        // 既に同名ファイルがある場合は上書きにする（Files アプリの「置き換え」相当）。
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }

        // 1. 書庫に埋め込むファイル実体を PageSource から集める。
        //    ArchiveFile.id には PageSource.id をそのまま使う。書き出し・読み込みの
        //    両方でこの id を使い回すだけで済み、別途対応表を持たずに済むため。
        var pendingFiles: [PendingFile] = []
        var seenIDs = Set<UUID>()

        var archiveScores: [ArchiveScore] = []
        for score in scores {
            var archiveSources: [ArchiveSource] = []
            for source in score.sources.sorted(by: { $0.order < $1.order }) {
                archiveSources.append(ArchiveSource(
                    fileID: source.id,
                    kind: source.kind.rawValue,
                    pageCount: source.pageCount,
                    order: source.order,
                    originalName: source.originalName
                ))
                if !seenIDs.contains(source.id) {
                    seenIDs.insert(source.id)
                    let fileURL = store.fileURL(for: source.relativePath)
                    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
                    let size = (attributes[.size] as? UInt64) ?? 0
                    pendingFiles.append(PendingFile(id: source.id, originalName: source.originalName, sourceURL: fileURL, size: size))
                }
            }

            let archivePageSettings = score.pageSettings.map {
                ArchivePageSetting(
                    pageIndex: $0.pageIndex,
                    cropX: $0.cropX,
                    cropY: $0.cropY,
                    cropWidth: $0.cropWidth,
                    cropHeight: $0.cropHeight,
                    rotation: $0.rotation
                )
            }
            let archiveAnnotations = score.annotations.map {
                ArchiveAnnotation(pageIndex: $0.pageIndex, drawingData: $0.drawingData)
            }

            archiveScores.append(ArchiveScore(
                title: score.title,
                composer: score.composer,
                ensemble: score.ensemble,
                tags: score.tags,
                createdAt: score.createdAt,
                lastPageIndex: score.lastPageIndex,
                tempoBPM: score.tempoBPM,
                timeSignature: score.timeSignature,
                sources: archiveSources,
                pageSettings: archivePageSettings,
                annotations: archiveAnnotations
            ))
        }

        // セットリストの各項目は、書き出し対象の scores 配列内での添字として記録する。
        // 曲がその書き出しに含まれていなければ nil にし、読み込み側で読み飛ばせるようにする。
        let scoreIndexByID: [UUID: Int] = Dictionary(uniqueKeysWithValues: scores.enumerated().map { ($1.id, $0) })
        let archiveSetlists: [ArchiveSetlist] = setlists.map { setlist in
            ArchiveSetlist(
                name: setlist.name,
                createdAt: setlist.createdAt,
                items: setlist.orderedItems.map { item in
                    ArchiveSetlistItem(
                        order: item.order,
                        note: item.note,
                        scoreIndex: item.score.flatMap { scoreIndexByID[$0.id] }
                    )
                }
            )
        }

        // 2. offset はマニフェスト自体のバイト長に依存し、マニフェストのバイト長は
        //    offset の桁数にわずかに依存する（循環）。offset は単調増加でしかありえず、
        //    桁数がずれるのはごく稀なので、数回反復すればすぐ収束する。
        var files = pendingFiles.map { ArchiveFile(id: $0.id, originalName: $0.originalName, offset: 0, size: $0.size) }
        var manifest = ArchiveManifest(
            version: ArchiveFormat.currentVersion,
            exportedAt: Date(),
            scores: archiveScores,
            setlists: archiveSetlists,
            files: files
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var manifestSize = try encoder.encode(manifest).count
        for _ in 0..<5 {
            var offset = UInt64(ArchiveFormat.headerPrefixSize) + UInt64(manifestSize)
            for index in files.indices {
                files[index].offset = offset
                offset += files[index].size
            }
            manifest.files = files
            let newSize = try encoder.encode(manifest).count
            if newSize == manifestSize { break }
            manifestSize = newSize
        }

        // 3. ヘッダ + マニフェストを書き、続けてファイル実体を offset の順に追記する。
        //    `ArchiveWriter` はどちらもチャンク単位の `FileHandle` I/O なので、
        //    数GBのPDFを積んでもピークメモリは一定に保たれる。
        //    ここから先はモデルに一切触れないため、まるごとメインスレッドの外へ出せる。
        let sourceURLs = pendingFiles.map(\.sourceURL)
        let finalManifest = manifest
        let destination = url

        try await Task.detached(priority: .userInitiated) {
            let handle = try ArchiveWriter.createHeader(manifest: finalManifest, at: destination)
            defer { try? handle.close() }

            let total = max(sourceURLs.count, 1)
            for (index, sourceURL) in sourceURLs.enumerated() {
                _ = try ArchiveWriter.appendFile(at: sourceURL, to: handle)
                if let progress {
                    await progress(Double(index + 1) / Double(total))
                }
            }
            if sourceURLs.isEmpty, let progress {
                await progress(1.0)
            }
        }.value
    }

    // MARK: - 読み込み

    /// 書庫を既存のライブラリに**追加**する。
    ///
    /// 既存の曲・セットリストは一切消さない。バックアップの読み込みでユーザーの
    /// 楽譜が消えるのは取り返しがつかない事故になるため（設計原則 P3）、
    /// 「置き換え」ではなく常に「追加」として実装している。重複が気になる場合は
    /// ユーザー自身が読み込み後に手動で整理する前提。
    ///
    /// `async` なのは export と同じ理由で、書庫の展開がファイル I/O だからである。
    func importArchive(
        from url: URL,
        progress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws -> (scoreCount: Int, setlistCount: Int) {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let manifest = try ArchiveReader.readManifest(from: url)

        // 1. ファイル実体を ScoreStore の管理下に展開する。
        //    `ArchiveReader.extractFile` は書庫から読んだそばから書き出し先へ流すだけで、
        //    ファイル全体を一度に Data として抱えない（数GB級のPDFがあり得るため）。
        let totalSteps = max(manifest.files.count + manifest.scores.count, 1)
        let entries = manifest.files
        let store = self.store
        let archiveURL = url

        let relativePathByFileID: [UUID: String] = try await Task.detached(priority: .userInitiated) {
            var mapping: [UUID: String] = [:]
            var completed = 0
            for file in entries {
                let ext = URL(fileURLWithPath: file.originalName).pathExtension
                let relativePath = "\(UUID().uuidString).\(ext.isEmpty ? "dat" : ext.lowercased())"
                let destinationURL = store.fileURL(for: relativePath)
                try ArchiveReader.extractFile(file, from: archiveURL, to: destinationURL)
                try Self.excludeFromBackup(destinationURL)
                mapping[file.id] = relativePath

                completed += 1
                if let progress {
                    await progress(Double(completed) / Double(totalSteps))
                }
            }
            return mapping
        }.value

        var completedSteps = entries.count

        // 2. Score / PageSource / PageSetting / AnnotationLayer を作り直す。
        var importedScores: [Score] = []
        for archiveScore in manifest.scores {
            let score = Score(
                title: archiveScore.title,
                composer: archiveScore.composer,
                ensemble: archiveScore.ensemble,
                tags: archiveScore.tags
            )
            score.createdAt = archiveScore.createdAt
            score.updatedAt = Date()
            score.lastPageIndex = archiveScore.lastPageIndex
            score.tempoBPM = archiveScore.tempoBPM
            score.timeSignature = archiveScore.timeSignature
            modelContext.insert(score)

            for archiveSource in archiveScore.sources {
                guard let relativePath = relativePathByFileID[archiveSource.fileID] else {
                    // 実体が書庫内に見つからない場合、この曲の他ページはそのまま活かし、
                    // 欠けたページだけ落として続行する（1曲丸ごと失うより実害が小さい）。
                    Log.backup.error("書庫に実体が無いファイルを参照する曲があります: \(archiveScore.title, privacy: .public)")
                    continue
                }
                let source = PageSource(
                    relativePath: relativePath,
                    kind: PageSource.Kind(rawValue: archiveSource.kind) ?? .pdf,
                    pageCount: archiveSource.pageCount,
                    order: archiveSource.order,
                    originalName: archiveSource.originalName
                )
                source.score = score
                score.sources.append(source)
                modelContext.insert(source)
            }

            for archiveSetting in archiveScore.pageSettings {
                let setting = PageSetting(
                    pageIndex: archiveSetting.pageIndex,
                    cropRect: CGRect(
                        x: archiveSetting.cropX,
                        y: archiveSetting.cropY,
                        width: archiveSetting.cropWidth,
                        height: archiveSetting.cropHeight
                    ),
                    rotation: archiveSetting.rotation
                )
                setting.score = score
                score.pageSettings.append(setting)
                modelContext.insert(setting)
            }

            for archiveAnnotation in archiveScore.annotations {
                let annotation = AnnotationLayer(
                    pageIndex: archiveAnnotation.pageIndex,
                    drawingData: archiveAnnotation.drawingData
                )
                annotation.score = score
                score.annotations.append(annotation)
                modelContext.insert(annotation)
            }

            importedScores.append(score)
            completedSteps += 1
            progress?(Double(completedSteps) / Double(totalSteps))
        }

        // 3. セットリストを作り直す。scoreIndex は書き出し時点の scores 配列への添字。
        for archiveSetlist in manifest.setlists {
            let setlist = Setlist(name: archiveSetlist.name)
            setlist.createdAt = archiveSetlist.createdAt
            modelContext.insert(setlist)

            for archiveItem in archiveSetlist.items {
                let item = SetlistItem(order: archiveItem.order, note: archiveItem.note)
                if let scoreIndex = archiveItem.scoreIndex, importedScores.indices.contains(scoreIndex) {
                    item.score = importedScores[scoreIndex]
                }
                item.setlist = setlist
                setlist.items.append(item)
                modelContext.insert(item)
            }
        }

        try modelContext.save()
        progress?(1.0)

        return (scoreCount: importedScores.count, setlistCount: manifest.setlists.count)
    }

    /// iCloud バックアップから除外する。楽譜PDFは容量が大きく、原本はユーザー自身が
    /// 持っている（書き出しファイル自体が正規の退避手段）ため、`ScoreStore.importFile` と
    /// 同じ方針をここでも踏襲する。
    nonisolated static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

/// 書庫に埋め込む予定のファイル1件。
///
/// モデルから写し取った値型なので、メインアクタの外へそのまま渡せる。
private struct PendingFile: Sendable {
    let id: UUID
    let originalName: String
    let sourceURL: URL
    let size: UInt64
}
