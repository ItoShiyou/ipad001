import Foundation

/// 複数の入力方式を束ね、演奏ビューには単一のイベント列として渡す。
///
/// v1 で実際に繋ぐのはタップと HIDキーボードだけだが、
/// MIDI・iPhoneリモート・カメラ・タイムライン再生を後から
/// `register(_:)` するだけで足せるようにしてある。
@MainActor
final class PageTurnInputHub {
    private(set) var sources: [PageTurnInputSource] = []
    private var lastEventAt: [InputSourceKind: Date] = [:]

    /// 連続誤発火を防ぐ最小間隔。
    ///
    /// 人間が意図して2回めくる速度は塞がず、1操作が二重に届くのだけを落とす値にしている。
    var cooldown: TimeInterval = 0.12

    /// 受理されたイベントの届け先。
    var onEvent: ((PageTurnEvent) -> Void)?

    /// 自動系の入力が、直近の手動操作にどれだけ道を譲るか（設計原則 P6）。
    var manualOverrideWindow: TimeInterval = 3.0
    private var lastManualEventAt: Date?

    func register(_ source: PageTurnInputSource) {
        source.handler = { [weak self] event in
            self?.receive(event)
        }
        sources.append(source)
    }

    func activateAll() {
        sources.forEach { $0.activate() }
    }

    func deactivateAll() {
        sources.forEach { $0.deactivate() }
    }

    func source(of kind: InputSourceKind) -> PageTurnInputSource? {
        sources.first { $0.kind == kind }
    }

    /// 現在有効な入力方式。演奏ビューのインジケータ（FR-86）に出す。
    var activeKinds: [InputSourceKind] {
        sources.filter(\.isActive).map(\.kind)
    }

    private func receive(_ event: PageTurnEvent) {
        if let last = lastEventAt[event.source],
           event.timestamp.timeIntervalSince(last) < cooldown {
            Log.input.debug("cooldown で破棄: \(event.source.rawValue, privacy: .public)")
            return
        }

        // P6: 人間が触った直後は、自動系のめくりを通さない。
        // 奏者が手で位置を直したのに、直後に自動が上書きするのが最悪の挙動であるため。
        if !event.source.isManual,
           let manual = lastManualEventAt,
           event.timestamp.timeIntervalSince(manual) < manualOverrideWindow {
            Log.input.debug("手動操作直後のため自動入力を抑止: \(event.source.rawValue, privacy: .public)")
            return
        }

        lastEventAt[event.source] = event.timestamp
        if event.source.isManual {
            lastManualEventAt = event.timestamp
        }
        onEvent?(event)
    }
}
