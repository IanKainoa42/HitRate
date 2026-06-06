import AudioToolbox
import Foundation

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
