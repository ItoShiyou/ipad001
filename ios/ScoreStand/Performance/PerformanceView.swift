import SwiftUI

/// 演奏ビュー。**本番中に見える唯一の画面。**
///
/// 画面上の要素を極端に絞っているのは、暗いステージで見ずに操作するため
/// （設計原則 P5）。設定に類するものは一切ここに置かない。
struct PerformanceView: View {
    @State private var model: PerformanceViewModel
    @State private var showsControls = false
    /// 注釈の編集中。編集中はタップが注釈に取られるため、
    /// 譜めくりはペダルとキーボードだけになる。演奏中に入る想定ではない。
    @State private var isAnnotating = false
    @Environment(PerformanceSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// FR-14（ベータ）: 暗転中の客席への配慮で画面の明るさを下げる。
    /// 演奏を終えたら必ず元に戻す（`onDisappear`）。スライダーではなく数段階の
    /// 循環ボタンにしているのは、暗所で細かい操作をさせないため（P5）。
    @State private var brightnessLevelIndex = 0
    private static let brightnessLevels: [CGFloat] = [1.0, 0.6, 0.3, 0.12]
    @State private var originalBrightness: CGFloat = UIScreen.main.brightness

    private let hub: PageTurnInputHub
    private let tapSource: TapInputSource
    private let keyboardSource: KeyboardInputSource

    init(
        model: PerformanceViewModel,
        hub: PageTurnInputHub,
        tapSource: TapInputSource,
        keyboardSource: KeyboardInputSource
    ) {
        _model = State(initialValue: model)
        self.hub = hub
        self.tapSource = tapSource
        self.keyboardSource = keyboardSource
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                PageImageView(
                    page: model.displayedPage,
                    secondaryPage: model.displayedSecondaryPage,
                    // 書き込み中は譜面も注釈も反転を止め、両方まとめて通常表示にする。
                    // 譜面だけ反転したまま注釈だけ非反転にすると、書き込みを終えた
                    // 瞬間に注釈の色だけ唐突に変わって見え、何が起きたか分からない
                    // （実機で指摘）。書き込みモードの切り替えそのものを
                    // 「反転⇔非反転が画面全体でまとまって起きる」動きにすることで、
                    // 色の変化が反転のせいだと直感的に伝わるようにする。
                    isInverted: model.isInverted && !isEffectivelyEditing
                )
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        tapSource.handleTap(at: location.x, width: proxy.size.width)
                    }
                    .gesture(swipeGesture)

                // 注釈は譜面の上に重ねるだけで、譜面自体には触れない（FR-41）。
                if let score = model.score {
                    AnnotationOverlay(
                        score: score,
                        pageIndex: model.currentPageIndex,
                        isEditing: isEffectivelyEditing,
                        isVisible: model.showsAnnotations,
                        isInverted: model.isInverted && !isEffectivelyEditing
                    )
                }

                if showsControls {
                    VStack(spacing: 0) {
                        controlBar
                        if !model.setlistTitles.isEmpty {
                            setlistJumpBar
                        }
                        if !model.jumpPoints.isEmpty {
                            jumpPointsBar
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if session.isLocked {
                    lockIndicator
                }

                if model.isWaitingForRender {
                    // 描画待ちを小さく示すだけに留める。大きな待ち表示は
                    // 「止まった」と誤解させ、奏者を不安にさせるため。
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding()
                }
            }
            .onAppear {
                originalBrightness = UIScreen.main.brightness
                model.updateLayout(size: proxy.size, scale: displayScale)
                // 配線を先に済ませてから活性化する。逆順だと、
                // 開いた直後に踏まれたペダルの1回目を取りこぼす。
                hub.onEvent = { event in
                    model.handle(event)
                }
                model.onAppear()
                hub.activateAll()
            }
            .onChange(of: proxy.size) { _, newSize in
                model.updateLayout(size: newSize, scale: displayScale)
            }
            .onChange(of: model.isTwoPageSpread) { _, _ in
                model.spreadModeChanged()
            }
        }
        .background(.black)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .ignoresSafeArea()
        .onDisappear {
            hub.deactivateAll()
            model.onDisappear()
            // 演奏ビューを閉じたら明るさは必ず元に戻す。落とした状態が
            // 他の画面まで持ち越されると、無関係な操作に気づけなくなる。
            UIScreen.main.brightness = originalBrightness
        }
        // フットスイッチ・Bluetoothリモコンはキーボードとして届く（FR-21 / FR-28）。
        .background(KeyCommandCatcher(source: keyboardSource))
    }

    @Environment(\.displayScale) private var displayScale

    /// ロック中は書き込みモードに入れない（FR-25）ため、`isAnnotating` の
    /// 値だけでは実際に編集可能かどうかを判定できない。1箇所にまとめて、
    /// 譜面・注釈の反転判定で同じ条件を確実に使い回す。
    private var isEffectivelyEditing: Bool {
        isAnnotating && !session.isLocked
    }

    private func cycleBrightness() {
        brightnessLevelIndex = (brightnessLevelIndex + 1) % Self.brightnessLevels.count
        UIScreen.main.brightness = Self.brightnessLevels[brightnessLevelIndex]
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    // 縦方向の大きなスワイプは操作バーの開閉に使う。
                    // 譜めくりと衝突しない軸を選んでいる。
                    // ロック中は開かない（FR-25: 譜めくり以外を無効化する）。
                    guard !session.isLocked else { return }
                    withAnimation(.easeOut(duration: 0.15)) { showsControls.toggle() }
                    return
                }
                tapSource.handleSwipe(isForward: value.translation.width < 0)
            }
    }

    private var controlBar: some View {
        HStack(spacing: 20) {
            Button {
                dismiss()
            } label: {
                Label("閉じる", systemImage: "xmark")
            }

            Spacer()

            if let position = model.setlistPosition {
                Text("\(position.index + 1) / \(position.total)")
                    .monospacedDigit()
            }
            Text("\(model.currentPageIndex + 1) / \(max(model.pageCount, 1))")
                .monospacedDigit()

            Spacer()

            Toggle(isOn: $model.isInverted) {
                Label("反転", systemImage: "circle.lefthalf.filled")
            }
            .labelsHidden()
            .toggleStyle(.button)

            Button {
                cycleBrightness()
            } label: {
                Label("明るさ", systemImage: "sun.max")
            }

            Toggle(isOn: $model.isTwoPageSpread) {
                Label("見開き", systemImage: "book")
            }
            .labelsHidden()
            .toggleStyle(.button)

            // FR-42: 注釈の表示・非表示。書き込みを消さずに譜面だけを見たい場面がある。
            Toggle(isOn: $model.showsAnnotations) {
                Label("注釈", systemImage: model.showsAnnotations ? "pencil.circle.fill" : "pencil.slash")
            }
            .labelsHidden()
            .toggleStyle(.button)

            // FR-40 / FR-45: 注釈の書き込み。
            Button {
                isAnnotating.toggle()
                if isAnnotating { model.showsAnnotations = true }
            } label: {
                Label(
                    isAnnotating ? "書き込み中" : "書き込む",
                    systemImage: isAnnotating ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle"
                )
            }

            // FR-25: 誤操作防止ロック。譜めくり以外を止める。
            Button {
                session.isLocked.toggle()
                if session.isLocked {
                    // ロックした瞬間に、譜めくり以外の状態から抜けておく。
                    // 「ロックしたのに書き込みモードのままだった」が本番では事故になる。
                    isAnnotating = false
                    withAnimation(.easeOut(duration: 0.15)) { showsControls = false }
                }
            } label: {
                Label(
                    session.isLocked ? "ロック中" : "ロック",
                    systemImage: session.isLocked ? "lock.fill" : "lock.open"
                )
            }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .foregroundStyle(.primary)
    }
}

extension PerformanceView {
    /// 演奏中にセットリストの任意の曲へ飛ぶ（FR-32）。
    ///
    /// 曲名を大きめの丸ボタンで横に並べているのは、暗所で狙って押せる面積が要るため。
    fileprivate var setlistJumpBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(model.setlistTitles.enumerated()), id: \.offset) { index, title in
                    Button {
                        model.jumpToSetlistItem(at: index)
                    } label: {
                        Text("\(index + 1). \(title)")
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                index == model.setlistPosition?.index ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }

    /// リピート / D.S. / Coda などへ1操作で飛ぶ（FR-26、ベータ）。
    /// セットリストのジャンプバーと同じ「大きな丸ボタンを横に並べる」形にして、
    /// 暗所でも押しやすい面積を確保している。
    fileprivate var jumpPointsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(model.jumpPoints, id: \.id) { point in
                    Button {
                        model.goToPage(point.pageIndex)
                    } label: {
                        Text(point.label.isEmpty ? "\(point.pageIndex + 1)ページ目" : point.label)
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }

    /// ロック中であることの控えめな表示。
    ///
    /// 解除を長押しにしているのは、ロックの目的が誤タップ防止だからである。
    /// タップで解除できるなら、そもそも誤タップから守れない。
    ///
    /// 以前は `.frame(maxWidth: .infinity, maxHeight: .infinity)` の後に
    /// `.onLongPressGesture` を付けており、`.contentShape` も無かったため
    /// 当たり判定が不確実だった。背後の譜面ビュー（画面全体を覆うタップ・
    /// スワイプジェスチャを持つ）と競合し、実機で長押しが認識されず
    /// ロックから抜けられなくなる事故が起きた。円のアイコンそのものに
    /// 明示的な `contentShape` を与え、VStack/HStack + Spacer で
    /// 右上に配置することで、当たり判定の範囲をこの円だけに確実に絞る。
    fileprivate var lockIndicator: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.title2)
                    .padding(16)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
                    .onLongPressGesture(minimumDuration: 1.0) {
                        session.isLocked = false
                    }
                    .accessibilityLabel("ロック中。長押しで解除")
            }
            Spacer()
        }
        .padding()
    }
}

/// `UIKeyCommand` を拾うためだけの透明なビュー。
///
/// SwiftUI の `.onKeyPress` は対象キーの表現が限られるため、
/// ペダルが送る矢印キーや Page Up/Down を確実に受けるには UIKit 側で受ける方が堅い。
private struct KeyCommandCatcher: UIViewControllerRepresentable {
    let source: KeyboardInputSource

    func makeUIViewController(context: Context) -> KeyCommandViewController {
        let controller = KeyCommandViewController()
        controller.source = source
        return controller
    }

    func updateUIViewController(_ uiViewController: KeyCommandViewController, context: Context) {
        uiViewController.source = source
    }
}

private final class KeyCommandViewController: UIViewController {
    var source: KeyboardInputSource?

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override var keyCommands: [UIKeyCommand]? {
        guard let source else { return nil }
        return source.allKeys.map { key in
            let command = UIKeyCommand(input: key, modifierFlags: [], action: #selector(handleKey(_:)))
            // ペダルを踏んだときにシステム音が鳴らないようにする。
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
    }

    @objc private func handleKey(_ command: UIKeyCommand) {
        guard let input = command.input else { return }
        _ = source?.handleKey(input)
    }
}
