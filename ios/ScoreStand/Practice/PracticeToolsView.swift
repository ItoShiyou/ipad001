import SwiftUI

/// メトロノーム + チューナー（FR-50〜54）。
///
/// **ベータ実装**: いずれも S 優先度。同時に使える（FR-52）ことを重視し、
/// 1つの細いカードにまとめて表示する（FR-54: 譜面表示を妨げない配置）。
struct PracticeToolsView: View {
    @Bindable var score: Score

    @State private var metronome = MetronomeEngine()
    @State private var tuner = TunerEngine()
    @State private var tunerError: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("この機能はベータです。動作は今後変わる可能性があります。", systemImage: "wrench.and.screwdriver")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("メトロノーム") {
                    Stepper(value: $metronome.bpm, in: MetronomeEngine.bpmRange) {
                        LabeledContent("テンポ", value: "\(metronome.bpm) BPM")
                    }
                    Stepper(value: $metronome.beatsPerBar, in: 1...12) {
                        LabeledContent("拍子", value: "\(metronome.beatsPerBar)拍子")
                    }
                    Toggle("1拍目にアクセント", isOn: $metronome.accentFirstBeat)

                    HStack {
                        beatIndicator
                        Spacer()
                        Button {
                            metronome.toggle()
                        } label: {
                            Label(
                                metronome.isRunning ? "停止" : "開始",
                                systemImage: metronome.isRunning ? "stop.fill" : "play.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Section("チューナー") {
                    Stepper(value: $tuner.referenceA4, in: 415...466, step: 1) {
                        LabeledContent("基準ピッチ（A4）", value: "\(Int(tuner.referenceA4)) Hz")
                    }

                    if let error = tunerError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        tunerReadout
                        Spacer()
                        Button {
                            toggleTuner()
                        } label: {
                            Label(
                                tuner.isRunning ? "停止" : "開始",
                                systemImage: tuner.isRunning ? "stop.fill" : "mic.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Section("この曲のテンポ・拍子") {
                    Stepper(
                        value: Binding(
                            get: { score.tempoBPM ?? 120 },
                            set: { score.tempoBPM = $0 }
                        ),
                        in: MetronomeEngine.bpmRange
                    ) {
                        LabeledContent("記憶するテンポ", value: score.tempoBPM.map { "\($0) BPM" } ?? "未設定")
                    }
                    TextField("拍子（例: 4/4）", text: Binding(
                        get: { score.timeSignature ?? "" },
                        set: { score.timeSignature = $0.isEmpty ? nil : $0 }
                    ))
                }
            }
            .navigationTitle("練習ツール")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .onAppear {
            // この曲に記憶されたテンポがあれば、開いた時点でメトロノームに反映する（FR-53）。
            if let tempo = score.tempoBPM {
                metronome.bpm = tempo
            }
        }
        .onDisappear {
            metronome.stop()
            tuner.stop()
        }
    }

    private var beatIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<metronome.beatsPerBar, id: \.self) { beat in
                Circle()
                    .fill(beat == metronome.currentBeat && metronome.isRunning ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)
            }
        }
    }

    private var tunerReadout: some View {
        Group {
            if let reading = tuner.reading {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(reading.noteName)\(reading.octave)")
                        .font(.title2.monospacedDigit())
                        .bold()
                    Text(centsLabel(for: reading.cents))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(abs(reading.cents) < 5 ? .green : .secondary)
                }
            } else if tuner.isRunning {
                Text("音を聴いています…")
                    .foregroundStyle(.secondary)
            } else {
                Text("停止中")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func centsLabel(for cents: Double) -> String {
        let rounded = Int(cents.rounded())
        if rounded == 0 { return "±0" }
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }

    private func toggleTuner() {
        if tuner.isRunning {
            tuner.stop()
            return
        }
        do {
            tunerError = nil
            try tuner.start()
        } catch {
            tunerError = "マイクを使用できませんでした。設定アプリでマイクの許可を確認してください。"
        }
    }
}
