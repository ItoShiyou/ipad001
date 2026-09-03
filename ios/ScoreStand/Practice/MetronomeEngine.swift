import AVFoundation
import Foundation

/// メトロノーム（FR-50、ベータ）。
///
/// **ベータ実装**: 設計書（`docs/requirements.md`）の S 優先度機能。M（v1必須）ではないため、
/// 実機での長時間動作・他アプリとの音声セッション競合は未検証。
///
/// `Timer` ではなく `AVAudioEngine` のサンプル精度スケジューリングで刻む。
/// `Timer`/`DispatchSourceTimer` は OS のスケジューリング揺らぎ（数〜数十ms）を
/// そのまま拍のずれとして聴かせてしまうため、テンポキープの道具として使い物にならない。
/// 数拍先まで前もってバッファをスケジュールしておく（look-ahead）ことで、
/// 描画スレッドや他の処理が詰まっても音のタイミングは影響を受けない。
@MainActor
@Observable
final class MetronomeEngine {
    private(set) var isRunning = false
    private(set) var currentBeat = 0

    /// 1分あたりの拍数。
    ///
    /// `didSet` 内で自分自身に代入すると、クランプ後の値が現在値と同じでも
    /// 必ずもう一度 `didSet` が呼ばれ、無限再帰でスタックオーバーフローする。
    /// 変化があるときだけ代入することで再帰を1回で止める。
    var bpm: Int = 120 {
        didSet {
            let clamped = bpm.clamped(to: Self.bpmRange)
            if clamped != bpm { bpm = clamped }
        }
    }
    /// 1小節の拍数（拍子の分子）。理由は `bpm` と同じ。
    var beatsPerBar: Int = 4 {
        didSet {
            let clamped = max(1, min(beatsPerBar, 16))
            if clamped != beatsPerBar { beatsPerBar = clamped }
        }
    }
    var accentFirstBeat: Bool = true

    static let bpmRange = 30...300

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var accentBuffer: AVAudioPCMBuffer?
    private var normalBuffer: AVAudioPCMBuffer?

    /// look-ahead スケジューリングの状態。
    private var nextBeatSampleTime: AVAudioFramePosition = 0
    private var nextBeatIndex = 0
    private var schedulerTask: Task<Void, Never>?

    private let sampleRate: Double = 44100

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        accentBuffer = Self.makeClickBuffer(frequency: 1800, format: format)
        normalBuffer = Self.makeClickBuffer(frequency: 1200, format: format)
    }

    /// 短いクリック音を波形として合成する。外部音源ファイルを持ち込まずに済ませるため。
    /// 立ち上がり・立ち下がりを短いフェードにしているのは、矩形波的な急変で
    /// スピーカーがクリックノイズを立てるのを避けるため。
    private static func makeClickBuffer(frequency: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration = 0.03
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let data = buffer.floatChannelData?[0] else { return nil }

        let fadeSamples = Int(format.sampleRate * 0.004)
        for i in 0..<Int(frameCount) {
            let t = Double(i) / format.sampleRate
            var amplitude = sin(2 * .pi * frequency * t)
            if i < fadeSamples {
                amplitude *= Double(i) / Double(fadeSamples)
            } else if i > Int(frameCount) - fadeSamples {
                amplitude *= Double(Int(frameCount) - i) / Double(fadeSamples)
            }
            data[i] = Float(amplitude * 0.6)
        }
        return buffer
    }

    /// 演奏開始。`countInBars` 小節分は音を鳴らすだけで `currentBeat` の進行を
    /// 呼び出し側に見せない、という区別はせず、単純に頭から刻む
    /// （カウントインの見た目の扱いは呼び出し側 UI に委ねる）。
    func start() {
        guard !isRunning else { return }
        do {
            try configureAudioSession()
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            Log.performance.error("メトロノームの音声起動に失敗: \(error.localizedDescription, privacy: .public)")
            return
        }

        isRunning = true
        currentBeat = 0
        nextBeatIndex = 0
        nextBeatSampleTime = player.lastRenderTime
            .flatMap { player.playerTime(forNodeTime: $0) }?.sampleTime ?? 0
        if !player.isPlaying { player.play() }

        schedulerTask = Task { [weak self] in
            while let self, self.isRunning {
                self.scheduleAheadIfNeeded()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stop() {
        isRunning = false
        schedulerTask?.cancel()
        schedulerTask = nil
        player.stop()
        currentBeat = 0
    }

    func toggle() {
        if isRunning { stop() } else { start() }
    }

    /// 次の数拍分をあらかじめスケジュールする。100msごとに呼ばれ、
    /// 常に「今から約1秒先」までバッファが積まれている状態を保つ。
    private func scheduleAheadIfNeeded() {
        guard let accentBuffer, let normalBuffer else { return }
        let beatInterval = 60.0 / Double(bpm)
        let beatSamples = AVAudioFramePosition(beatInterval * sampleRate)
        let lookAheadSamples = AVAudioFramePosition(1.0 * sampleRate)

        guard let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return }
        let horizon = playerTime.sampleTime + lookAheadSamples

        while nextBeatSampleTime < horizon {
            let beatInBar = nextBeatIndex % beatsPerBar
            let buffer = (beatInBar == 0 && accentFirstBeat) ? accentBuffer : normalBuffer
            let when = AVAudioTime(sampleTime: nextBeatSampleTime, atRate: sampleRate)
            let beatIndexForUpdate = nextBeatIndex
            player.scheduleBuffer(buffer, at: when, options: []) { [weak self] in
                Task { @MainActor in
                    guard let self, self.isRunning else { return }
                    self.currentBeat = beatIndexForUpdate % self.beatsPerBar
                }
            }
            nextBeatSampleTime += beatSamples
            nextBeatIndex += 1
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        // チューナーと同時に使える必要がある（FR-52）ため、再生専用ではなく
        // .playAndRecord にしておく。チューナーが後から入力タップを張っても
        // カテゴリの変更で互いのセッションを壊さないようにするため。
        try session.setCategory(.playAndRecord, options: [.mixWithOthers, .defaultToSpeaker])
        try session.setActive(true)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
