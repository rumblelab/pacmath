import AVFoundation

// ---------------------------------------------------------------------------
//  AudioManager – synthesised sound effects for PacMath
//
//  Generates short WAV data on the fly and plays via AVAudioPlayer,
//  which coexists safely with SpeechRecognizer's AVAudioEngine.
// ---------------------------------------------------------------------------

class AudioManager {

    static let shared = AudioManager()

    private let sampleRate: Double = 44_100

    // Pre-rendered WAV data so playback is instant.
    private var correctData: Data?
    private var wrongData: Data?

    private var player: AVAudioPlayer?
    private var lastPlayTime: Date = .distantPast

    // MARK: - Init

    private init() {
        correctData = renderCorrectSound()
        wrongData = renderWrongSound()
    }

    // MARK: - Public API

    func playCorrect() {
        guard let data = correctData else { return }
        play(data)
    }

    func playWrong() {
        guard let data = wrongData else { return }
        play(data)
    }

    // MARK: - Playback

    private func play(_ data: Data) {
        // Debounce: ignore rapid-fire plays within 200ms
        let now = Date()
        guard now.timeIntervalSince(lastPlayTime) > 0.2 else { return }
        lastPlayTime = now

        do {
            player = try AVAudioPlayer(data: data)
            player?.play()
        } catch {
            print("AudioManager: playback failed – \(error)")
        }
    }

    // MARK: - WAV rendering

    private func renderCorrectSound() -> Data? {
        let duration = 0.30
        let frameCount = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: frameCount)

        let tone1Freq = 523.0, tone1Dur = 0.18
        let tone2Start = 0.12, tone2Freq = 659.0, tone2Dur = 0.18

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate

            // Tone 1
            if t < tone1Dur {
                let gain = lerp(0.25, 0.001, t / tone1Dur)
                samples[i] += Float(gain * sin(2.0 * .pi * tone1Freq * t))
            }

            // Tone 2
            let t2 = t - tone2Start
            if t2 >= 0 && t2 < tone2Dur {
                let gain = lerp(0.25, 0.001, t2 / tone2Dur)
                samples[i] += Float(gain * sin(2.0 * .pi * tone2Freq * t2))
            }
        }

        return wavData(from: samples)
    }

    private func renderWrongSound() -> Data? {
        let duration = 0.25
        let frameCount = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: frameCount)

        var phase = 0.0
        for i in 0..<frameCount {
            let progress = Double(i) / Double(frameCount)
            let freq = lerp(180.0, 100.0, progress)
            let gain = lerp(0.12, 0.001, progress)
            phase += freq / sampleRate
            phase -= Double(Int(phase))
            samples[i] = Float(gain * (2.0 * phase - 1.0))
        }

        return wavData(from: samples)
    }

    // MARK: - WAV encoding

    private func wavData(from samples: [Float]) -> Data {
        let numSamples = samples.count
        // Convert to 16-bit PCM
        var pcm = [Int16](repeating: 0, count: numSamples)
        for i in 0..<numSamples {
            let clamped = max(-1.0, min(1.0, samples[i]))
            pcm[i] = Int16(clamped * Float(Int16.max))
        }

        var data = Data()
        let dataSize = numSamples * 2
        let fileSize = 36 + dataSize

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(uint32: UInt32(fileSize))
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(uint32: 16)              // chunk size
        data.append(uint16: 1)               // PCM format
        data.append(uint16: 1)               // mono
        data.append(uint32: UInt32(sampleRate))
        data.append(uint32: UInt32(sampleRate * 2)) // byte rate
        data.append(uint16: 2)               // block align
        data.append(uint16: 16)              // bits per sample

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(uint32: UInt32(dataSize))
        for sample in pcm {
            var s = sample
            data.append(Data(bytes: &s, count: 2))
        }

        return data
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}

// MARK: - Data helpers

private extension Data {
    mutating func append(uint16 value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }
    mutating func append(uint32 value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
