import XCTest
@testable import ScoreStand

final class TunerEngineTests: XCTestCase {
    func testExactA4IsZeroCents() {
        let reading = TunerEngine.reading(for: 440, referenceA4: 440)
        XCTAssertEqual(reading.noteName, "A")
        XCTAssertEqual(reading.octave, 4)
        XCTAssertEqual(reading.cents, 0, accuracy: 0.01)
    }

    func testSlightlySharpA4() {
        // 440Hzから半音の約1/4上（約6セント相当）だけ高い周波数。
        let reading = TunerEngine.reading(for: 441.5, referenceA4: 440)
        XCTAssertEqual(reading.noteName, "A")
        XCTAssertGreaterThan(reading.cents, 0)
        XCTAssertLessThan(reading.cents, 20)
    }

    func testMiddleCIsRecognized() {
        // C4（中央ド）はA4の9半音下 ≈ 261.63Hz。
        let reading = TunerEngine.reading(for: 261.63, referenceA4: 440)
        XCTAssertEqual(reading.noteName, "C")
        XCTAssertEqual(reading.octave, 4)
        XCTAssertEqual(reading.cents, 0, accuracy: 1.0)
    }

    func testCustomReferencePitchShiftsNoteBoundaries() {
        // 基準A4を442Hzにすると、440Hzはわずかに低いAとして読まれる。
        let reading = TunerEngine.reading(for: 440, referenceA4: 442)
        XCTAssertEqual(reading.noteName, "A")
        XCTAssertLessThan(reading.cents, 0)
    }

    // MARK: - detectPitch（自己相関）

    func testDetectPitchFindsKnownSineFrequency() throws {
        let sampleRate = 44100.0
        let trueFrequency = 220.0 // A3
        let samples = Self.sineWave(frequency: trueFrequency, sampleRate: sampleRate, seconds: 0.1)

        let detected = TunerEngine.detectPitch(in: samples, sampleRate: sampleRate)

        let detectedValue = try XCTUnwrap(detected)
        // 自己相関 + 放物線補間の精度として1Hz以内を要求する。
        XCTAssertEqual(detectedValue, trueFrequency, accuracy: 1.0)
    }

    func testDetectPitchReturnsNilForSilence() {
        let samples = [Float](repeating: 0, count: 4096)
        XCTAssertNil(TunerEngine.detectPitch(in: samples, sampleRate: 44100))
    }

    private static func sineWave(frequency: Double, sampleRate: Double, seconds: Double) -> [Float] {
        let count = Int(sampleRate * seconds)
        return (0..<count).map { i in
            Float(sin(2 * .pi * frequency * Double(i) / sampleRate))
        }
    }
}
