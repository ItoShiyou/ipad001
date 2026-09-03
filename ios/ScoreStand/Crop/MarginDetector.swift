import CoreGraphics
import Foundation

/// ページ画像の余白（白地）を検出し、内容のある領域を正規化矩形で返す。
/// 状態を持たないため enum（namespace）として定義する。
enum MarginDetector {
    /// 縮小後の長辺の目標サイズ。原寸のまま全画素を走査すると
    /// 譜面のような高解像度画像では非常に重くなるため、まず縮小してから走査する。
    private static let maxScanDimension = 600

    /// `image` の中で `threshold` より暗い画素が存在する範囲を、正規化した CGRect (0...1) で返す。
    /// 全面が閾値以上に明るい（=白い）場合は原寸大の矩形 (0,0,1,1) を返す。
    static func detectContentRect(in image: CGImage, threshold: UInt8 = 240) -> CGRect {
        let originalWidth = image.width
        let originalHeight = image.height
        guard originalWidth > 0, originalHeight > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let longSide = max(originalWidth, originalHeight)
        let scale = longSide > maxScanDimension ? Double(maxScanDimension) / Double(longSide) : 1.0
        let width = max(1, Int(Double(originalWidth) * scale))
        let height = max(1, Int(Double(originalHeight) * scale))

        // グレースケールの1バイト/画素バッファに描き直す。
        // これにより「暗い画素かどうか」の判定を単純なバイト比較だけで行える。
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray) else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        // withUnsafeMutableBytes のポインタを閉包の外に持ち出すのは危険なため、
        // CGContext 自身が確保・保持するバッファを使う（copy(from:) で読み出す）。
        let byteCount = width * height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let contextData = context.data else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var pixels = [UInt8](repeating: 255, count: byteCount)
        pixels.withUnsafeMutableBytes { dest in
            dest.copyMemory(from: UnsafeRawBufferPointer(start: contextData, count: byteCount))
        }

        var minX = width
        var maxX = -1
        var minY = height
        var maxY = -1

        for y in 0..<height {
            let rowStart = y * width
            for x in 0..<width {
                if pixels[rowStart + x] < threshold {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        // 暗い画素が見つからなければ全面白と判断する。
        guard maxX >= minX, maxY >= minY else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let normMinX = Double(minX) / Double(width)
        let normMaxX = Double(maxX + 1) / Double(width)
        let normMinY = Double(minY) / Double(height)
        let normMaxY = Double(maxY + 1) / Double(height)

        // 検出した矩形ぴったりで切ると、音符の符尾や小節線の端がわずかに欠けて
        // 読みにくくなるため、数%のパディングを外側に足しておく。
        let padding = 0.02
        let paddedMinX = max(0, normMinX - padding)
        let paddedMinY = max(0, normMinY - padding)
        let paddedMaxX = min(1, normMaxX + padding)
        let paddedMaxY = min(1, normMaxY + padding)

        return CGRect(
            x: paddedMinX,
            y: paddedMinY,
            width: paddedMaxX - paddedMinX,
            height: paddedMaxY - paddedMinY
        )
    }
}
