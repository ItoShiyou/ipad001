import CoreGraphics
import Foundation
import PDFKit
import UIKit

/// PDFと画像を、表示用のビットマップに変換する。
///
/// `PDFDocument` は同一インスタンスへの並行アクセスが安全でないため、
/// この actor の中に閉じ込めて直列化している。開いたドキュメントは
/// 使い回す（500ページのPDFを毎回開き直すと NFR-01 を満たせない）。
actor PageRenderer {
    private let store: ScoreStore
    private var openDocuments: [String: PDFDocument] = [:]
    /// 同時に開いたままにするPDFの数。曲をまたいでめくっても開き直しが起きない程度に留める。
    private let maxOpenDocuments = 4
    private var documentUseOrder: [String] = []

    init(store: ScoreStore) {
        self.store = store
    }

    /// 曲を閉じたとき、その実体を解放する。
    func closeDocuments(for descriptors: [PageDescriptor]) {
        for path in Set(descriptors.map(\.relativePath)) {
            openDocuments.removeValue(forKey: path)
            documentUseOrder.removeAll { $0 == path }
        }
    }

    func closeAll() {
        openDocuments.removeAll()
        documentUseOrder.removeAll()
    }

    /// 1ページを描画する。
    ///
    /// `Task.isCancelled` を要所で見ているのは、めくりが速いときに
    /// 追い越された描画を捨てるため。捨てないと古いページが後から現れる。
    func render(_ descriptor: PageDescriptor, key: RenderKey) throws -> RenderedPage {
        try Task.checkCancellation()

        let content: CGImage
        switch descriptor.kind {
        case .pdf:
            content = try renderPDF(descriptor, key: key)
        case .image:
            content = try renderImage(descriptor, key: key)
        }

        return RenderedPage(
            scoreID: descriptor.scoreID,
            pageIndex: descriptor.pageIndex,
            renderKey: key,
            image: content
        )
    }

    // MARK: - PDF

    private func renderPDF(_ descriptor: PageDescriptor, key: RenderKey) throws -> CGImage {
        let document = try document(at: descriptor.relativePath)
        guard let page = document.page(at: descriptor.pageInSource) else {
            throw RenderError.pageMissing(descriptor.pageIndex)
        }

        // メディアボックスに対する正規化矩形として切り抜きを解釈する。
        // 正規化して持つことで、用紙サイズの違う楽譜が混ざっても同じ設定が通用する。
        let bounds = page.bounds(for: .mediaBox)
        let crop = CGRect(
            x: bounds.minX + descriptor.cropRect.minX * bounds.width,
            y: bounds.minY + descriptor.cropRect.minY * bounds.height,
            width: descriptor.cropRect.width * bounds.width,
            height: descriptor.cropRect.height * bounds.height
        )

        try Task.checkCancellation()

        let rotation = (descriptor.rotation + page.rotation) % 360
        let swapsAxes = rotation == 90 || rotation == 270
        let sourceSize = swapsAxes
            ? CGSize(width: crop.height, height: crop.width)
            : crop.size
        let target = Self.fit(sourceSize, into: key.pixelSize)

        let renderer = UIGraphicsImageRenderer(size: target, format: Self.format())
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(origin: .zero, size: target))

            cg.translateBy(x: 0, y: target.height)
            cg.scaleBy(x: 1, y: -1)

            let scaleX = target.width / sourceSize.width
            let scaleY = target.height / sourceSize.height
            cg.scaleBy(x: scaleX, y: scaleY)

            switch rotation {
            case 90:
                cg.translateBy(x: 0, y: crop.width)
                cg.rotate(by: -.pi / 2)
            case 180:
                cg.translateBy(x: crop.width, y: crop.height)
                cg.rotate(by: .pi)
            case 270:
                cg.translateBy(x: crop.height, y: 0)
                cg.rotate(by: .pi / 2)
            default:
                break
            }

            cg.translateBy(x: -crop.minX, y: -crop.minY)
            // PDFPage.draw は自身の rotation を適用してしまうため、ここでは使わない。
            // 回転はこちらで一度だけ掛ける。
            if let pageRef = page.pageRef {
                cg.drawPDFPage(pageRef)
            }
        }

        guard let cgImage = image.cgImage else {
            throw RenderError.rasterizationFailed(descriptor.pageIndex)
        }
        return cgImage
    }

    // MARK: - 画像

    private func renderImage(_ descriptor: PageDescriptor, key: RenderKey) throws -> CGImage {
        let url = store.fileURL(for: descriptor.relativePath)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw RenderError.fileUnreadable(descriptor.relativePath)
        }

        // 元画像を丸ごとメモリに載せず、必要な寸法にサムネイル化して受け取る。
        // 大きな写真の楽譜でも NFR-03 のメモリ上限を超えないようにするため。
        let maxPixel = Int(max(key.pixelSize.width, key.pixelSize.height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]

        try Task.checkCancellation()

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw RenderError.rasterizationFailed(descriptor.pageIndex)
        }

        if descriptor.cropRect == CGRect(x: 0, y: 0, width: 1, height: 1) && descriptor.rotation == 0 {
            return thumbnail
        }
        return try applyCropAndRotation(to: thumbnail, descriptor: descriptor)
    }

    private func applyCropAndRotation(to image: CGImage, descriptor: PageDescriptor) throws -> CGImage {
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let crop = CGRect(
            x: descriptor.cropRect.minX * full.width,
            y: descriptor.cropRect.minY * full.height,
            width: descriptor.cropRect.width * full.width,
            height: descriptor.cropRect.height * full.height
        ).integral

        guard let cropped = image.cropping(to: crop) else {
            throw RenderError.rasterizationFailed(descriptor.pageIndex)
        }
        guard descriptor.rotation != 0 else { return cropped }

        let swapsAxes = descriptor.rotation == 90 || descriptor.rotation == 270
        let size = swapsAxes
            ? CGSize(width: cropped.height, height: cropped.width)
            : CGSize(width: cropped.width, height: cropped.height)

        let renderer = UIGraphicsImageRenderer(size: size, format: Self.format())
        let rotated = renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: CGFloat(descriptor.rotation) * .pi / 180)
            cg.translateBy(x: -CGFloat(cropped.width) / 2, y: -CGFloat(cropped.height) / 2)
            cg.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        }
        guard let result = rotated.cgImage else {
            throw RenderError.rasterizationFailed(descriptor.pageIndex)
        }
        return result
    }

    // MARK: - ドキュメントの保持

    private func document(at relativePath: String) throws -> PDFDocument {
        if let existing = openDocuments[relativePath] {
            documentUseOrder.removeAll { $0 == relativePath }
            documentUseOrder.append(relativePath)
            return existing
        }

        let url = store.fileURL(for: relativePath)
        guard let document = PDFDocument(url: url) else {
            throw RenderError.fileUnreadable(relativePath)
        }

        openDocuments[relativePath] = document
        documentUseOrder.append(relativePath)
        while documentUseOrder.count > maxOpenDocuments {
            let evicted = documentUseOrder.removeFirst()
            openDocuments.removeValue(forKey: evicted)
        }
        return document
    }

    // MARK: - 補助

    /// `preferred()` は trait collection を読むためメインアクタに縛られうる。
    /// この actor はメインスレッドの外で回すので、素の format を自分で組む。
    private static func format() -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        // スケールは呼び出し側が RenderKey で決めている。ここで二重に掛けない。
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return format
    }

    /// 縦横比を保ったまま収める。楽譜は歪むと読めないので引き伸ばしはしない。
    private static func fit(_ size: CGSize, into bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return bounds }
        let ratio = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(
            width: max(1, (size.width * ratio).rounded()),
            height: max(1, (size.height * ratio).rounded())
        )
    }
}

enum RenderError: LocalizedError {
    case pageMissing(Int)
    case fileUnreadable(String)
    case rasterizationFailed(Int)

    var errorDescription: String? {
        switch self {
        case .pageMissing(let index):
            return "\(index + 1)ページ目が見つかりません。"
        case .fileUnreadable(let path):
            return "楽譜ファイルを読み込めません（\(path)）。"
        case .rasterizationFailed(let index):
            return "\(index + 1)ページ目を描画できませんでした。"
        }
    }
}
