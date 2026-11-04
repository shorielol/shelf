import AVFoundation
import Foundation

/// Tiny UI sounds synthesised at launch. Every sound is generated here, so no audio files ship with the app.
final class Sounds {
    static let shared = Sounds()

    enum Effect: CaseIterable {
        case tick, thud, clack, needle, pop
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "uiSounds") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "uiSounds") }
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var isStarted = false

    private init() {
        for effect in Effect.allCases { buffers[effect] = synthesize(effect) }
        for _ in 0..<4 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = 0.55
    }

    func play(_ effect: Effect, volume: Float = 1) {
        guard isEnabled, let buffer = buffers[effect] else { return }
        if !isStarted {
            do { try engine.start(); isStarted = true } catch { return }
        }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    private func synthesize(_ effect: Effect) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let duration: Double = switch effect {
        case .tick: 0.018
        case .thud: 0.22
        case .clack: 0.05
        case .needle: 0.6
        case .pop: 0.09
        }
        let frames = AVAudioFrameCount(rate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        var noiseState: UInt32 = 0x1234_5678
        func noise() -> Float {
            noiseState ^= noiseState << 13; noiseState ^= noiseState >> 17; noiseState ^= noiseState << 5
            return Float(noiseState) / Float(UInt32.max) * 2 - 1
        }
        var lowpass: Float = 0
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let sample: Float
            switch effect {
            case .tick:
                // A dry plastic detent: filtered noise burst with a fast decay.
                lowpass += 0.5 * (noise() - lowpass)
                sample = lowpass * Float(exp(-t * 380)) * 0.9
            case .thud:
                // A soft landing: a low sine that drops in pitch, plus a little felt.
                let pitch = 92 * exp(-t * 6) + 48
                sample = Float(sin(2 * .pi * pitch * t) * exp(-t * 18)) * 0.9 + noise() * Float(exp(-t * 90)) * 0.08
            case .clack:
                // A split-flap card: two quick filtered snaps.
                lowpass += 0.35 * (noise() - lowpass)
                let snap = exp(-t * 260) + 0.6 * exp(-max(0, t - 0.018) * 300) * (t > 0.018 ? 1 : 0)
                sample = lowpass * Float(snap) * 1.1
            case .needle:
                // Needle drop: a muffled bump, then a few crackles fading out.
                let bump = sin(2 * .pi * 60 * t) * exp(-t * 25) * 0.6
                let crackle: Double = noise() > 0.985 ? Double(noise()) * 0.5 : 0
                lowpass += 0.2 * (noise() - lowpass)
                sample = Float(bump + crackle * exp(-t * 3)) + lowpass * Float(0.05 * exp(-t * 4))
            case .pop:
                let pitch = 520 + 380 * t * 10
                sample = Float(sin(2 * .pi * pitch * t) * exp(-t * 45)) * 0.5
            }
            data[i] = sample
        }
        return buffer
    }
}
