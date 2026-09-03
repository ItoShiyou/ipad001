import SwiftUI

/// 演奏ビュー。**本番中に見える唯一の画面。**
///
/// 画面上の要素を極端に絞っているのは、暗いステージで見ずに操作するため
/// （設計原則 P5）。設定に類するものは一切ここに置かない。
struct PerformanceView: View {
    @State private var model: PerformanceViewModel
    @State private var showsControls = false
    @Environment(PerformanceSession.self) private var session
    @Environment(\.dismiss) private var dismiss

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
                PageImageView(page: model.displayedPage, isInverted: model.isInverted)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        tapSource.handleTap(at: location.x, width: proxy.size.width)
                    }
                    .gesture(swipeGesture)

                if showsControls {
                    controlBar
                        .transition(.move(edge: .top).combined(with: .opacity))
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
        }
        .background(.black)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .ignoresSafeArea()
        .onDisappear {
            hub.deactivateAll()
            model.onDisappear()
        }
        // フットスイッチ・Bluetoothリモコンはキーボードとして届く（FR-21 / FR-28）。
        .background(KeyCommandCatcher(source: keyboardSource))
    }

    @Environment(\.displayScale) private var displayScale

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    // 縦方向の大きなスワイプは操作バーの開閉に使う。
                    // 譜めくりと衝突しない軸を選んでいる。
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

            Toggle(isOn: $model.isTwoPageSpread) {
                Label("見開き", systemImage: "book")
            }
            .labelsHidden()
            .toggleStyle(.button)

            // FR-25: 誤操作防止ロック。譜めくり以外を止める。
            Button {
                session.isLocked.toggle()
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
