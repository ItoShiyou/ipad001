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

    /// ページスクラバーをドラッグ中の一時的な値。ドラッグ中は毎ピクセルで
    /// 実際のページ送り（先読み込み）を起こさず、指を離した瞬間だけ
    /// `model.goToPage` を呼ぶ（P1: 演奏中の重い処理を避ける）。
    @State private var scrubValue: Double?

    /// ロック解除の確認ダイアログ（下の `lockIndicator` 参照）。
    @State private var isUnlockConfirmationPresented = false

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
                // 常に画面全体を覆う黒背景。コントロールバー表示中は譜面側に
                // 余白（padding）ができるが、そこもこの黒で埋まるので
                // 見た目には継ぎ目が出ない。
                Color.black.ignoresSafeArea()

                // 譜面と注釈は必ず同じ余白で一緒に縮小・移動させる。
                // 片方だけ縮めると、書き込んだ位置が譜面とずれて見える。
                //
                // ヘッダー・フッターの分だけ本体を縮めるのは、手計測した高さを
                // padding に渡す自前実装（GeometryReader + PreferenceKey）を
                // 最初に試したが、実機で反映されないことがあった。
                // `safeAreaInset` は同じ目的のために SwiftUI が用意している
                // 標準の仕組みで、挿入したバーの実サイズぶん本体コンテンツの
                // レイアウト領域を確実に縮めてくれるため、そちらに置き換えた。
                ZStack {
                    // `.id` + `.transition` は自動スクロール（新規要望）専用の演出。
                    // タップ・ドラッグ・ペダルなど手動の譜めくりは `withAnimation` で
                    // 包んでいないため、この `.id` が変わっても瞬時に切り替わるだけで
                    // アニメーションはしない（NFR-01: 手動操作にアニメーションを足すと
                    // 応答が遅く感じられる）。自動スクロール側だけが
                    // `PerformanceViewModel.startAutoScroll` 内で `withAnimation` を
                    // 使っており、そのときだけこの transition が効く。
                    //
                    // 「1,2 → 2,3 → 3,4」のように1ページずつ重ねて流れる本物の
                    // 連続スクロールは、実機で重大な不具合（ページ送りが止まる・
                    // 注釈が違うページに残る）を起こして一度撤回している
                    // （`docs/implementation-status.md` 参照）。同じ危険を避けるため、
                    // 実際のスクロール位置を追跡する仕組みは一切使わず、
                    // 「新旧2枚の静止画をスライドで入れ替える」だけの、
                    // ジェスチャと無関係な見た目だけのアニメーションに留めている。
                    // 見開きでは、右ページ（例: 2ページ目）が旧スプレッドの右端から
                    // 消えると同時に新スプレッドの左端に現れるため、重なって
                    // 連続しているように見える。
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
                        .id(model.currentPageIndex)
                        .transition(pageTransition(pageSize: proxy.size))
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
                        // 自動スクロール中だけ、譜面と同じ `.id` を与えて一緒にスライドさせる
                        // （実機での指摘: 注釈だけ追従せず取り残されて見えた）。
                        //
                        // 手動の譜めくりでは常に同じ固定値にして `.id` を変えない
                        // ようにしている。ここを常時 `currentPageIndex` にすると、
                        // ページを送るたびに `AnnotationCanvasView`（PencilKit の
                        // `PKCanvasView` を包む）が丸ごと作り直されることになり、
                        // 何度も実機のバグを踏んできたこの部分（ツールピッカーの
                        // 関連付け・Coordinatorの取り違えなど）に不要なリスクを
                        // 持ち込んでしまう。自動スクロール中だけの副作用に留める。
                        .id(model.isAutoScrolling ? model.currentPageIndex : -1)
                        .transition(pageTransition(pageSize: proxy.size))
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if showsControls {
                        VStack(spacing: 0) {
                            controlBar
                            if model.isAutoScrolling {
                                autoScrollSpeedBar
                            }
                            if !model.setlistTitles.isEmpty {
                                setlistJumpBar
                            }
                            if !model.jumpPoints.isEmpty {
                                jumpPointsBar
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if showsControls, model.pageCount > 1 {
                        pageScrubberBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.15), value: showsControls)

                if session.isLocked {
                    lockIndicator
                }

                // FR-98相当: 次の自動送りまでの残り時間を細いバーで予告する。
                // コントロールバーが隠れていても（＝暗所での本番中でも）見える
                // 位置に置く必要があるため、`showsControls` に関係なく出す。
                // 下端は開いている間ページスクラバーと重なるため、上端に置く。
                if model.isAutoScrolling {
                    autoScrollProgressBar
                        .frame(maxHeight: .infinity, alignment: .top)
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

    /// 自動スクロールの見た目の演出（上のコメント参照）。
    ///
    /// 縦置き（単ページ）は下から上へ、横置き（見開き）は右から左へ流れる。
    /// どちらも「新しいページ・見開きは進む方向の先から現れ、古い方は
    /// 同じ方向へ抜けていく」という向きに揃えている。
    ///
    /// 横置き（見開き）は `.move(edge:)` をやめ、見開き全体の**半分**
    /// （＝ページ1枚ぶん）だけ動かす `.offset` に変えている。見開きは
    /// 「2,3」→「3,4」のように中央のページ（3）が両方の見開きに
    /// またがって存在するため、見開き全体（2ページぶん）を丸ごと
    /// スライドさせると、3が一瞬完全に消えてから出てくるように見える
    /// （実機で指摘）。半分だけ動かせば、旧見開きの3と新見開きの3が
    /// 常に同じ位置に重なって動くため、切れ目なく1枚が横に滑るように見える。
    private func pageTransition(pageSize: CGSize) -> AnyTransition {
        model.isTwoPageSpread
            ? .asymmetric(insertion: .offset(x: pageSize.width / 2), removal: .offset(x: -pageSize.width / 2))
            : .asymmetric(insertion: .move(edge: .bottom), removal: .move(edge: .top))
    }

    /// 次の自動送りまでの残り時間を示す、細い進捗バー（新規要望、FR-98相当）。
    ///
    /// `TimelineView` で描画側だけを一定間隔で更新し、`PerformanceViewModel` 側は
    /// 「次に送る時刻」を1回書くだけにしている。ビューモデルを毎フレーム
    /// 更新すると、譜めくりと無関係な理由で `@Observable` の変更通知が
    /// 増えてしまう（NFR-01への影響を避けたい）。
    private var autoScrollProgressBar: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            GeometryReader { geo in
                let total = model.autoScrollSecondsPerPage
                let remaining = model.autoScrollDeadline?.timeIntervalSince(context.date) ?? 0
                let fraction = total > 0 ? min(1, max(0, 1 - remaining / total)) : 0
                // 楽譜は基本的に白背景なので、白いバーだと見えにくいという
                // 実機での指摘を受けて赤にした（目立たせるための色で、
                // エラーの意味ではない）。
                Rectangle()
                    .fill(Color.red)
                    .frame(width: geo.size.width * fraction)
            }
            .frame(height: 4)
        }
        .background(.black.opacity(0.2))
    }

    private func cycleBrightness() {
        brightnessLevelIndex = (brightnessLevelIndex + 1) % Self.brightnessLevels.count
        UIScreen.main.brightness = Self.brightnessLevels[brightnessLevelIndex]
    }

    /// スワイプ操作。譜めくり（新規要望）とコントロールバー開閉の両方をここで扱う。
    ///
    /// 縦置き（単ページ）は縦スワイプで譜めくり、横置き（見開き）は横スワイプで
    /// 譜めくりにする。使っていない方の軸をコントロールバー開閉に割り当てるのは
    /// 元の設計（「めくりと衝突しない軸を選ぶ」）と同じ考え方。
    ///
    /// 実際に画面に追従して流れる連続スクロール（`ScrollView` + 3枠の循環窓）を
    /// 一度実装したが、実機でページ送りが特定の範囲から進まなくなる・注釈が
    /// 違うページのまま表示され続けるという重大な不具合が出たため撤回した
    /// （`docs/implementation-status.md` 参照）。指を離した瞬間に1ページぶんだけ
    /// 送る、これまでと同じ「離散的な」めくりに留めている。
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let isPagingAxisDominant = model.isTwoPageSpread
                    ? abs(value.translation.width) > abs(value.translation.height)
                    : abs(value.translation.height) > abs(value.translation.width)
                if isPagingAxisDominant {
                    // FR-25: ロック中でも譜めくりだけは動く。ロック判定は
                    // 「コントロールバー開閉」側だけに掛け、こちらには掛けない。
                    // 一度両方まとめて `guard !session.isLocked` していたところ、
                    // ドラッグでの譜めくりまで一緒にロックされてしまう不具合が
                    // 実機で見つかった。
                    let isForward = model.isTwoPageSpread
                        ? value.translation.width < 0
                        : value.translation.height < 0
                    model.stopAutoScroll()
                    model.goToPage(model.currentPageIndex + (isForward ? 1 : -1) * (model.isTwoPageSpread ? 2 : 1))
                } else {
                    guard !session.isLocked else { return }
                    withAnimation(.easeOut(duration: 0.15)) { showsControls.toggle() }
                }
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

            // 自動スクロール（ベータ）: 見開きの手動切替に代わって、
            // 向き自動判定の見開きはここでは触らず、速度指定の自動送りを置いた。
            Button {
                model.toggleAutoScroll()
            } label: {
                Label(
                    model.isAutoScrolling ? "自動送り中" : "自動送り（β）",
                    systemImage: model.isAutoScrolling ? "pause.fill" : "play.fill"
                )
            }

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
                        model.stopAutoScroll()
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

    /// 自動送りの速度（新規要望、ベータ）。
    ///
    /// 自動送り中だけ出す。速いほど左、遅いほど右にしているのは
    /// スライダー慣習に合わせただけで、値そのものは「1ページ（見開きは1見開き）
    /// あたりの秒数」。演奏中に見て操作する前提の設定なので、コントロールバー
    /// 表示中（＝ロック解除中）にしか出さない。
    fileprivate var autoScrollSpeedBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "hare")
                .foregroundStyle(.secondary)
            Slider(
                value: $model.autoScrollSecondsPerPage,
                in: PerformanceViewModel.autoScrollRange
            )
            Image(systemName: "tortoise")
                .foregroundStyle(.secondary)
            Text("\(Int(model.autoScrollSecondsPerPage))秒/ページ")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    /// ページを一気に飛べるスクラバー（実機での要望で追加）。
    ///
    /// 大判の楽譜では1ページずつ送るより、狙ったページ付近まで一気に
    /// スライドできた方が速い。ドラッグ中は値をローカルの `scrubValue` に
    /// 留めておき、指を離した瞬間にだけ `model.goToPage` を呼ぶ
    /// （P1: ドラッグの1フレームごとに先読みを再計算させない）。
    private var pageScrubberBar: some View {
        let displayIndex = scrubValue.map(Int.init) ?? model.currentPageIndex
        return VStack(spacing: 4) {
            Text("\(displayIndex + 1) / \(max(model.pageCount, 1))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                // タップでのページ送りだけ、この数字が更新されない不具合が実機で
                // 見つかった（上部コントロールバーの同種の表示は正しく更新される）。
                // 原因を安全側に倒して潰すため、ページが変わるたびに `.id` で
                // このビュー自体を作り直させ、古い値が残る余地を無くす。
                .id(displayIndex)
            Slider(
                value: Binding(
                    get: { scrubValue ?? Double(model.currentPageIndex) },
                    set: { scrubValue = $0 }
                ),
                in: 0...Double(max(model.pageCount - 1, 0)),
                step: 1,
                onEditingChanged: { isEditing in
                    if !isEditing, let scrubValue {
                        model.stopAutoScroll()
                        model.goToPage(Int(scrubValue.rounded()))
                    }
                    self.scrubValue = nil
                }
            )
            .disabled(session.isLocked)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        // 下端ぎりぎりに置くと、iPadOS の Dock / App Switcher を呼ぶ
        // 下端スワイプとドラッグ操作が競合する（上端のコントロールバー開閉で
        // 一度経験した問題と同じ種類）。スライダーは特にドラッグの持続時間が
        // 長く巻き込まれやすいため、下端から離す余白を通常より大きく取る。
        .padding(.bottom, 28)
        .background(.ultraThinMaterial)
    }

    /// ロック中であることの控えめな表示。
    ///
    /// 解除にひと手間（確認）を挟んでいるのは、ロックの目的が誤タップ防止
    /// だからである。ワンタップで即解除できるなら、そもそも誤タップから守れない。
    ///
    /// **解除の実装方式の変遷（すべて実機で発覚した事故）**:
    /// 1. 当初は円に `.onLongPressGesture` を直付け（`.contentShape` 無し）→
    ///    背後の譜面ビューの全画面ジェスチャと当たり判定が競合し、長押しが
    ///    認識されずロックから抜けられなくなる事故が起きた。円だけに
    ///    `contentShape` を絞る形に直した。
    /// 2. 2026-09-06、譜めくりをドラッグでも行えるようにした際、ロック中も
    ///    そのドラッグ自体は動くようにした（FR-25）ことで、背後の
    ///    `swipeGesture`（`DragGesture`）が常に有効になり、上記と同種の
    ///    競合が実機で再発した。`.highPriorityGesture` + `LongPressGesture`
    ///    に直したが、それでも実機で解除に失敗することがあった。
    /// 3. `LongPressGesture` を捨て、`DragGesture(minimumDistance: 0)` で
    ///    自前のタイマーを起動する方式（指の動きに影響されない）に直したが、
    ///    **これでも実機で解除に失敗した**。ここまでで、SwiftUI の
    ///    ジェスチャ同士の優先度をどう調整しても信頼できないと判断した。
    /// 4. **最終形**: タップ（ジェスチャの競合に弱くない、ごく普通の1回タップ）
    ///    で `confirmationDialog` を出し、その中の「解除する」ボタンを押させる
    ///    2段階方式にした。システムのダイアログは表示中、背後のジェスチャを
    ///    一切受け付けない（OSが保証する動作であり、SwiftUI側の優先度指定に
    ///    依存しない）ため、原理的に競合しようがない。
    fileprivate var lockIndicator: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    isUnlockConfirmationPresented = true
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .padding(16)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .accessibilityLabel("ロック中。タップして解除")
            }
            Spacer()
        }
        .padding()
        .confirmationDialog(
            "ロックを解除しますか？",
            isPresented: $isUnlockConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("解除する", role: .destructive) {
                session.isLocked = false
            }
            Button("キャンセル", role: .cancel) {}
        }
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
