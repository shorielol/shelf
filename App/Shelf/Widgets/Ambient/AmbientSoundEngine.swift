import AVFoundation
import Observation
import os
import Synchronization

/// The sounds the generator can make. All of them are synthesised; nothing ships as audio.
nonisolated enum AmbientSound: String, CaseIterable, Identifiable, Sendable {
    case white, pink, brown, rain, fireplace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .white: "White"
        case .pink: "Pink"
        case .brown: "Brown"
        case .rain: "Rain"
        case .fireplace: "Fire"
        }
    }

    var symbol: String {
        switch self {
        case .white: "waveform"
        case .pink: "waveform.path"
        case .brown: "water.waves"
        case .rain: "cloud.rain"
        case .fireplace: "flame"
        }
    }

    var code: UInt8 {
        switch self {
        case .white: 0
        case .pink: 1
        case .brown: 2
        case .rain: 3
        case .fireplace: 4
        }
    }
}

/// One shared engine for every Ambient Sound widget. The audio hardware is only held while playing.
@Observable
final class AmbientSoundEngine {
    static let shared = AmbientSoundEngine()

    private(set) var isPlaying = false
    private(set) var sound: AmbientSound = .rain
    /// The widget that started playback, so other instances show themselves as idle.
    private(set) var owner: UUID?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private let renderer = NoiseRenderer()
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var configObserver: NSObjectProtocol?
    @ObservationIgnored private static let logger = Logger(subsystem: "app.shelf", category: "ambient-sound")
    /// Long enough for the gain ramp to reach silence before the engine stops.
    @ObservationIgnored private static let fadeOut: Duration = .milliseconds(350)

    private init() {}

    /// Current output level, 0...1. Cheap to read; poll it from a timeline while playing.
    var level: Float { renderer.level }

    func play(_ sound: AmbientSound, volume: Double, owner: UUID) {
        stopTask?.cancel()
        self.sound = sound
        self.owner = owner
        renderer.setKind(sound.code)
        renderer.setGain(Self.gain(for: volume))
        guard let engine = engine ?? makeEngine() else { return }
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                Self.logger.error("Couldn't start audio: \(error.localizedDescription)")
                isPlaying = false
                return
            }
        }
        isPlaying = true
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        renderer.setGain(0)
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: Self.fadeOut)
            guard let self, !Task.isCancelled, !self.isPlaying else { return }
            self.engine?.stop()
        }
    }

    func setSound(_ sound: AmbientSound) {
        self.sound = sound
        renderer.setKind(sound.code)
    }

    func setVolume(_ volume: Double) {
        guard isPlaying else { return }
        renderer.setGain(Self.gain(for: volume))
    }

    /// Slider position to linear gain; squared so the slider feels even to the ear.
    private static func gain(for volume: Double) -> Float {
        let v = Float(min(1, max(0, volume)))
        return v * v
    }

    private func makeEngine() -> AVAudioEngine? {
        let engine = AVAudioEngine()
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 44_100, channels: 2) else { return nil }
        renderer.prepare(sampleRate: Float(format.sampleRate))
        let source = Self.makeSourceNode(renderer: renderer, format: format)
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.prepare()
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAfterDeviceChange() }
        }
        self.engine = engine
        return engine
    }

    /// Output device changed (headphones in or out): the engine stops itself, so pick up again.
    private func restartAfterDeviceChange() {
        guard isPlaying, let engine, !engine.isRunning else { return }
        do { try engine.start() } catch {
            Self.logger.error("Couldn't restart audio: \(error.localizedDescription)")
            isPlaying = false
        }
    }

    /// Built outside the main actor so the render block carries no actor isolation.
    nonisolated private static func makeSourceNode(renderer: NoiseRenderer, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            renderer.render(frames: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(bufferList))
            return noErr
        }
    }
}

/// Shared between the main actor and the audio thread. Parameters cross as atomics;
/// the generator state is only ever touched on the audio thread.
nonisolated final class NoiseRenderer: @unchecked Sendable {
    private let kind = Atomic<UInt8>(3)
    private let targetGain = Atomic<UInt32>(0)
    private let rms = Atomic<UInt32>(0)
    private var left = NoiseVoice(seed: 0x9E37_79B9)
    private var right = NoiseVoice(seed: 0x85EB_CA6B)
    private var gain: Float = 0
    private var rampPerSample: Float = 0.0005

    func prepare(sampleRate: Float) {
        left.sampleRate = sampleRate
        right.sampleRate = sampleRate
        // About 50 ms to settle, whatever the rate.
        rampPerSample = 1 - exp(-1 / (0.05 * sampleRate))
    }

    func setKind(_ code: UInt8) { kind.store(code, ordering: .relaxed) }
    func setGain(_ value: Float) { targetGain.store(value.bitPattern, ordering: .relaxed) }
    var level: Float { min(1, Float(bitPattern: rms.load(ordering: .relaxed)) * 3.2) }

    /// Real-time: no allocation, no locks, no Objective-C.
    func render(frames: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        guard frames > 0, buffers.count > 0, let first = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let second = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        let code = kind.load(ordering: .relaxed)
        let target = Float(bitPattern: targetGain.load(ordering: .relaxed))
        var l = left, r = right, g = gain
        let ramp = rampPerSample
        var sum: Float = 0
        for i in 0..<frames {
            g += (target - g) * ramp
            let a = l.next(code) * g
            first[i] = a
            sum += a * a
            if let second {
                let b = r.next(code) * g
                second[i] = b
            }
        }
        left = l; right = r; gain = g
        rms.store(sqrt(sum / Float(frames)).bitPattern, ordering: .relaxed)
    }
}

/// One channel's worth of generator state.
nonisolated struct NoiseVoice {
    var sampleRate: Float = 44_100
    private var state: UInt32
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    private var brownLast: Float = 0
    private var dropEnv: Float = 0, dropPhase: Float = 0, dropStep: Float = 0
    private var crackEnv: Float = 0, crackHP: Float = 0, crackLast: Float = 0
    private var popEnv: Float = 0, popPhase: Float = 0
    private var flicker: Float = 0, flickerPhase: Float = 0

    init(seed: UInt32) { state = seed }

    mutating func next(_ code: UInt8) -> Float {
        let sample: Float = switch code {
        case 0: white() * 0.22
        case 1: pink()
        case 2: brown()
        case 3: rain()
        default: fireplace()
        }
        return max(-1, min(1, sample))
    }

    private mutating func random() -> Float {
        state ^= state << 13; state ^= state >> 17; state ^= state << 5
        return Float(state) / Float(UInt32.max)
    }

    private mutating func white() -> Float { random() * 2 - 1 }

    /// Paul Kellet's refined pink filter.
    private mutating func pink() -> Float {
        let w = white()
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        let out = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return out * 0.07
    }

    /// Integrated white noise with a little leak so it never drifts off.
    private mutating func brown() -> Float {
        brownLast = (brownLast + 0.02 * white()) / 1.02
        return brownLast * 2.6
    }

    /// Pink hiss for the downpour, plus drops: short sine blips whose pitch rises as the bubble closes.
    private mutating func rain() -> Float {
        let bed = pink() * 0.9
        if dropEnv < 0.002, random() < 32 / sampleRate {
            dropEnv = 0.08 + random() * 0.22
            dropStep = 2 * .pi * (1_400 + random() * 3_200) / sampleRate
            dropPhase = 0
        }
        var drop: Float = 0
        if dropEnv > 0.0005 {
            drop = sin(dropPhase) * dropEnv
            dropPhase += dropStep
            dropStep *= 1.00012
            dropEnv *= 0.9965
        }
        return bed + drop
    }

    /// A low brown rumble that breathes, sizzle, crackles, and the odd pop of a knot in the wood.
    private mutating func fireplace() -> Float {
        flickerPhase += 2 * .pi * 0.23 / sampleRate
        if flickerPhase > 2 * .pi { flickerPhase -= 2 * .pi }
        flicker += (random() - flicker) * 0.00004
        let rumble = brown() * (0.75 + 0.15 * sin(flickerPhase) + 0.25 * flicker)

        let w = white()
        crackHP = 0.6 * (crackHP + w - crackLast)
        crackLast = w
        if random() < 9 / sampleRate { crackEnv = 0.25 + random() * 0.7 }
        let sizzle: Float = random() < 900 / sampleRate ? crackHP * (0.03 + random() * 0.05) : 0
        let crackle = crackHP * crackEnv
        crackEnv *= 0.992

        if popEnv < 0.001, random() < 0.25 / sampleRate { popEnv = 0.6 + random() * 0.4; popPhase = 0 }
        var pop: Float = 0
        if popEnv > 0.001 {
            pop = sin(popPhase) * popEnv * 0.5 + crackHP * popEnv * 0.4
            popPhase += 2 * .pi * 180 / sampleRate
            popEnv *= 0.9985
        }
        return rumble + crackle + sizzle + pop
    }
}
