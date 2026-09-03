import SwiftUI

/// ページの余白を切り詰める画面（FR-11 / FR-12）。
///
/// 紙をスキャンした楽譜は余白が広く、そのままではiPadの画面で譜面が小さくなる。
/// 譜面が大きく見えることは、暗いステージでは可読性に直結する。
struct PageCropView: View {
    let score: Score
    let pageIndex: Int
    let preview: CGImage?
    let onSave: (CGRect) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var crop: CGRect
    @State private var isDetecting = false

    init(score: Score, pageIndex: Int, preview: CGImage?, onSave: @escaping (CGRect) -> Void) {
        self.score = score
        self.pageIndex = pageIndex
        self.preview = preview
        self.onSave = onSave
        let existing = score.setting(forPage: pageIndex)?.cropRect
        _crop = State(initialValue: existing ?? CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { proxy in
                    ZStack {
                        if let preview {
                            Image(decorative: preview, scale: 1, orientation: .up)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        }
                        CropRectangleOverlay(crop: $crop)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .background(.black)

                HStack {
                    Button {
                        detect()
                    } label: {
                        Label("余白を自動検出", systemImage: "wand.and.stars")
                    }
                    .disabled(preview == nil || isDetecting)

                    Spacer()

                    Button("全体に戻す") {
                        crop = CGRect(x: 0, y: 0, width: 1, height: 1)
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("\(pageIndex + 1)ページの余白")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(crop)
                        dismiss()
                    }
                }
            }
        }
    }

    private func detect() {
        guard let preview else { return }
        isDetecting = true
        // 検出は画素走査なのでメインスレッドから外す。
        // 画面が固まると「壊れた」と受け取られるため。
        Task.detached(priority: .userInitiated) {
            let rect = MarginDetector.detectContentRect(in: preview)
            await MainActor.run {
                crop = rect
                isDetecting = false
            }
        }
    }
}

/// 切り抜き範囲を四隅のハンドルで調整する。
private struct CropRectangleOverlay: View {
    @Binding var crop: CGRect

    var body: some View {
        GeometryReader { proxy in
            let frame = CGRect(
                x: crop.minX * proxy.size.width,
                y: crop.minY * proxy.size.height,
                width: crop.width * proxy.size.width,
                height: crop.height * proxy.size.height
            )

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.black.opacity(0.5))
                    .reverseMask {
                        Rectangle()
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }

                Rectangle()
                    .strokeBorder(.yellow, lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)

                handle(at: .topLeading, frame: frame, size: proxy.size)
                handle(at: .bottomTrailing, frame: frame, size: proxy.size)
            }
        }
    }

    /// ハンドルを大きめに取っているのは、指で掴むため。
    /// 見た目の点は小さくても、当たり判定は 44pt を下回らないようにする。
    private func handle(at corner: Alignment, frame: CGRect, size: CGSize) -> some View {
        let isTopLeading = corner == .topLeading
        let position = isTopLeading
            ? CGPoint(x: frame.minX, y: frame.minY)
            : CGPoint(x: frame.maxX, y: frame.maxY)

        return Circle()
            .fill(.yellow)
            .frame(width: 18, height: 18)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(position)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let x = min(max(value.location.x / size.width, 0), 1)
                        let y = min(max(value.location.y / size.height, 0), 1)
                        var rect = crop
                        if isTopLeading {
                            rect = CGRect(
                                x: min(x, crop.maxX - 0.05),
                                y: min(y, crop.maxY - 0.05),
                                width: crop.maxX - min(x, crop.maxX - 0.05),
                                height: crop.maxY - min(y, crop.maxY - 0.05)
                            )
                        } else {
                            rect = CGRect(
                                x: crop.minX,
                                y: crop.minY,
                                width: max(x - crop.minX, 0.05),
                                height: max(y - crop.minY, 0.05)
                            )
                        }
                        crop = rect
                    }
            )
    }
}

private extension View {
    /// 指定した形の内側だけを切り抜く（明るい部分＝残す範囲）。
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            ZStack {
                Rectangle()
                mask().blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}
