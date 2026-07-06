import Foundation

#if os(iOS)
    import AVFoundation
#endif

/// Owns the iOS `AVAudioSession` category/activation and reacts to
/// interruptions (phone calls, other apps) and route changes (headphones
/// unplugged). Talks back to `PlayerController` purely through plain
/// closures set by the controller — this type never holds a reference to
/// the controller itself.
///
/// macOS has no audio-session concept, so every member below is a no-op
/// there (internal `#if os(iOS)`s, not a whole-file one) — `PlayerController`
/// can hold and call this type unconditionally on both platforms.
@MainActor
final class AudioSessionCoordinator {
    var onPauseRequested: (() -> Void)?
    var onResumeRequested: (() -> Void)?

    #if os(iOS)
        private var didActivate = false
    #endif

    init() {
        #if os(iOS)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInterruption),
                name: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance()
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRouteChange),
                name: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance()
            )
        #endif
    }

    deinit {
        #if os(iOS)
            NotificationCenter.default.removeObserver(self)
        #endif
    }

    /// Activates the shared audio session for playback, once. Safe to call
    /// on every `play()`; only the first call does any work. No-op on macOS.
    func ensureActive() {
        #if os(iOS)
            guard !didActivate else { return }
            didActivate = true
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)
        #endif
    }

    #if os(iOS)
        @objc private func handleInterruption(_ notification: Notification) {
            guard
                let info = notification.userInfo,
                let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: typeValue)
            else { return }

            switch type {
            case .began:
                onPauseRequested?()
            case .ended:
                let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    onResumeRequested?()
                }
            @unknown default:
                break
            }
        }

        @objc private func handleRouteChange(_ notification: Notification) {
            guard
                let info = notification.userInfo,
                let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
            else { return }

            if reason == .oldDeviceUnavailable {
                onPauseRequested?()
            }
        }
    #endif
}
