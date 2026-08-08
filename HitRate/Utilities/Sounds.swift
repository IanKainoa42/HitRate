import AudioToolbox
import CoreHaptics
import Foundation

/// Severity-aware tap haptics — the finger tells a hit from a fall without
/// looking, mirroring the per-outcome tap sounds. Custom Core Haptics
/// transients, NOT the SensoryFeedback presets: the `.error` preset's wobbly
/// triple-buzz read as sloppy on the floor (Ian, 2026-08-08). Every outcome is
/// a clean BUMP — severity changes the weight and attack, and a major fall is
/// a hard one-two knock. Call `play(_:)` where a rep is logged/staged; generic
/// UI taps keep the views' plain `hapticTrigger` medium impact.
///
/// Tuning: `intensity` is strength (0–1), `sharpness` is attack — 1 is a
/// razor snap, 0 is a soft round thud.
final class Haptics {
    static let shared = Haptics()
    private var engine: CHHapticEngine?
    private init() {}

    func play(_ outcome: Outcome) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try ensureEngine()
            let player = try engine.makePlayer(with: pattern(for: outcome))
            try player.start(atTime: 0)
        } catch {
            // Haptics are garnish — a stopped engine or transient failure
            // should never interrupt logging.
        }
    }

    /// One transient (tap) event.
    private func tap(intensity: Float, sharpness: Float, at time: TimeInterval = 0) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient,
                      parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                      ],
                      relativeTime: time)
    }

    private func pattern(for outcome: Outcome) throws -> CHHapticPattern {
        let events: [CHHapticEvent] = switch outcome {
        case .hit:                                       // light razor tick
            [tap(intensity: 0.55, sharpness: 1.0)]
        case .bobble:                                    // rounder mid bump
            [tap(intensity: 0.7, sharpness: 0.4)]
        case .buildingFall:                              // full-weight thud
            [tap(intensity: 1.0, sharpness: 0.5)]
        case .majorFall:                                 // hard one-two knock
            [tap(intensity: 1.0, sharpness: 1.0),
             tap(intensity: 1.0, sharpness: 1.0, at: 0.09)]
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    /// Lazily (re)build the engine. Backgrounding stops it and system resets
    /// invalidate it — both handlers just drop the reference so the next play
    /// starts fresh.
    private func ensureEngine() throws -> CHHapticEngine {
        if let e = engine { return e }
        let e = try CHHapticEngine()
        e.playsHapticsOnly = true
        e.resetHandler = { [weak self] in self?.engine = nil }
        e.stoppedHandler = { [weak self] _ in self?.engine = nil }
        try e.start()
        engine = e
        return e
    }
}

/// Tap sounds for the counter — the system keyboard-click family (the same
/// subtle ticks the iOS keyboard makes). No bundled assets; like keyboard
/// clicks they respect the ring/silent switch and mix over the gym's music.
///
/// The pad rotates the three click voices and never repeats the one it just
/// played — hammering reps sounds organic, exactly like fast typing does.
final class Sounds {
    static let shared = Sounds()

    enum Event: Hashable {
        case outcome(Outcome)
        case undo, start, end
    }

    static let defaultsKey = "soundsOn"

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true
    }

    /// System keyboard clicks: 1104 = standard tock, 1103 = lighter tick,
    /// 1105 = modifier tock.
    private let clicks: [SystemSoundID] = [1104, 1103, 1105]
    private var lastClick = -1

    private init() {}

    func play(_ event: Event) {
        guard enabled else { return }
        switch event {
        case .outcome:
            var i = Int.random(in: 0..<clicks.count)
            if i == lastClick { i = (i + 1) % clicks.count }
            lastClick = i
            AudioServicesPlaySystemSound(clicks[i])
        case .undo:
            AudioServicesPlaySystemSound(1103)
        case .start:
            AudioServicesPlaySystemSound(1104)
        case .end:
            AudioServicesPlaySystemSound(1105)
        }
    }
}
