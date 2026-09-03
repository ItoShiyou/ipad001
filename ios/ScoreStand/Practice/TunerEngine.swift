import AVFoundation
import Accelerate
import Foundation

/// 検出したピッチを、平均律の最近傍の音名と偏差（セント）に変換したもの。
struct TunerReading: Equatable {
    let noteName: String
    let octave: Int
    let cents: Double
    let frequency: Double
}

/// チューナー（FR-51、ベータ）。
///
/// **ベータ実装**: S 優先度機能。マイク入力からのピッチ検出は自己相関法による
/// 簡易実装で、和音・強いノイズ環境・極端に低い/高い音では精度が落ちる。
/// 実機のマイク特性・演奏環境での検証はまだ済んでいない。
@MainActor
@Observable
final class TunerEngine {
    private(set) var isRunning = false
    private(set) var reading: TunerReading?

    /// 基準ピッチ（A4）。既定 440Hz、調整可能にする（FR-51）。
    var referenceA4: Double = 440

    private let engine = AVAudioEngine()
    private let minFrequency: Double = 60   // チェロ・ベースの低音域まで
    private let maxFrequency: Double = 1500 // 高音域の楽器まで

    private nonisolated static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    func start() throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.mixWithOthers, .defaultToSpeaker])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        // 4096サンプルはA1（55Hz付近）でも数周期分を確保でき、自己相関の精度を保てる。
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            // タップのコールバックはリアルタイムのオーディオスレッドで呼ばれる。
            // 自己相関の計算はサンプル数×ラグ数のオーダーで重く、ここで同期実行すると
            // オーディオのドロップアウト（"ブツッ"というノイズ）を起こしうる。
            // サンプル配列へのコピーだけその場で済ませ、実際の解析は別スレッドへ逃がす。
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))

            Task.detached(priority: .userInitiated) {
                let frequency = Self.detectPitch(in: samples, sampleRate: sampleRate)
                await MainActor.run {
                    self?.handle(detectedFrequency: frequency)
                }
            }
        }
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        reading = nil
    }

    private func handle(detectedFrequency: Double?) {
        guard let frequency = detectedFrequency,
              frequency >= minFrequency, frequency <= maxFrequency else {
            reading = nil
            return
        }
        reading = Self.reading(for: frequency, referenceA4: referenceA4)
    }

    /// 周波数を、指定した基準A4のもとでの最近傍の平均律音名 + セント偏差に変換する。
    /// `Metrics`/`RenderKey` と同様、副作用のない純粋関数にして単体テストできるようにしている。
    nonisolated static func reading(for frequency: Double, referenceA4: Double) -> TunerReading {
        // A4 を基準に、半音単位の距離を対数で求める。
        let semitonesFromA4 = 12 * log2(frequency / referenceA4)
        let roundedSemitones = semitonesFromA4.rounded()
        let cents = (semitonesFromA4 - roundedSemitones) * 100

        // MIDI ノート番号（A4 = 69）に変換し、そこから音名とオクターブを出す。
        let midiNote = 69 + Int(roundedSemitones)
        let noteIndex = ((midiNote % 12) + 12) % 12
        let octave = midiNote / 12 - 1

        return TunerReading(
            noteName: noteNames[noteIndex],
            octave: octave,
            cents: cents,
            frequency: frequency
        )
    }

    /// 自己相関法によるピッチ検出。
    ///
    /// FFTベースのケプストラム法より実装が単純で、単音（楽器のロングトーン）に対しては
    /// 十分な精度が出る。和音や強い倍音成分が乗る音色では誤検出しやすい既知の弱点がある。
    nonisolated static func detectPitch(in samples: [Float], sampleRate: Double) -> Double? {
        let frameCount = samples.count
        guard frameCount > 0 else { return nil }

        // 無音・非常に小さい信号では検出しない（ノイズフロアでランダムな値を出さないため）。
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameCount))
        guard rms > 0.01 else { return nil }

        let minLag = Int(sampleRate / 1500)  // maxFrequency 相当
        let maxLag = Int(sampleRate / 60)    // minFrequency 相当
        guard maxLag < frameCount else { return nil }

        // `samples[lag...]` の都度スライスはヒープ確保を伴うため、生ポインタ + オフセットで
        // 直接 vDSP に渡す。1回のピッチ検出で数百ラグ分回るのでここは効いてくる。
        let (bestLag, bestCorrelation): (Int, Float) = samples.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            var bestLag = -1
            var bestCorrelation: Float = 0
            for lag in minLag...maxLag {
                var sum: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &sum, vDSP_Length(frameCount - lag))
                if sum > bestCorrelation {
                    bestCorrelation = sum
                    bestLag = lag
                }
            }
            return (bestLag, bestCorrelation)
        }

        guard bestLag > 0 else { return nil }

        // 放物線補間で lag をサブサンプル精度に補正する。整数ラグのままだと
        // 高い音ほど周波数分解能が粗くなり、セント表示がガタつく。
        let refined = parabolicInterpolate(samples: samples, lag: bestLag, peakCorrelation: bestCorrelation, frameCount: frameCount)
        return sampleRate / refined
    }

    private nonisolated static func parabolicInterpolate(samples: [Float], lag: Int, peakCorrelation: Float, frameCount: Int) -> Double {
        guard lag > 0, lag < frameCount - 1 else { return Double(lag) }

        func correlation(at lag: Int) -> Float {
            guard lag > 0, lag < frameCount else { return 0 }
            return samples.withUnsafeBufferPointer { buf in
                var sum: Float = 0
                vDSP_dotpr(buf.baseAddress!, 1, buf.baseAddress! + lag, 1, &sum, vDSP_Length(frameCount - lag))
                return sum
            }
        }

        let y0 = correlation(at: lag - 1)
        let y1 = peakCorrelation
        let y2 = correlation(at: lag + 1)
        let denominator = y0 - 2 * y1 + y2
        guard denominator != 0 else { return Double(lag) }
        let offset = 0.5 * (y0 - y2) / denominator
        return Double(lag) + Double(offset)
    }
}
