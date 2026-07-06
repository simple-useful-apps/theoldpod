import Foundation
import MediaPlayer
import PlaybackEngine

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Bridges `PlayerController` to the system: `MPRemoteCommandCenter` (lock
/// screen / Control Center / media keys) and `MPNowPlayingInfoCenter` (now
/// playing metadata + artwork).
@MainActor
public final class NowPlayingBridge {
    private let player: PlayerController
    private let artworkDirectory: URL?
    private var isActive = false
    private var cachedArtwork: (id: String, artwork: MPMediaItemArtwork)?

    public init(player: PlayerController, artworkDirectory: URL?) {
        self.player = player
        self.artworkDirectory = artworkDirectory
    }

    public func activate() {
        guard !isActive else { return }
        isActive = true
        registerCommandHandlers()
        scheduleNowPlayingInfoUpdate()
    }

    public func deactivate() {
        guard isActive else { return }
        isActive = false

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func registerCommandHandlers() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [player] _ in
            guard player.current != nil else { return .noSuchContent }
            if !player.isPlaying { player.togglePlayPause() }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [player] _ in
            guard player.current != nil else { return .noSuchContent }
            if player.isPlaying { player.togglePlayPause() }
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [player] _ in
            guard player.current != nil else { return .noSuchContent }
            player.togglePlayPause()
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [player] _ in
            guard player.current != nil else { return .noSuchContent }
            player.next()
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [player] _ in
            guard player.current != nil else { return .noSuchContent }
            player.previous()
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [player] event in
            guard player.current != nil, let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .noSuchContent
            }
            player.seek(to: event.positionTime)
            return .success
        }
    }

    /// Standard `withObservationTracking` re-arming pattern: read the
    /// observed properties while pushing now-playing info, then re-register
    /// on the next change. `isActive` is the guard that stops the loop from
    /// re-arming once `deactivate()` has been called.
    private func scheduleNowPlayingInfoUpdate() {
        guard isActive else { return }
        withObservationTracking {
            pushNowPlayingInfo()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleNowPlayingInfoUpdate()
            }
        }
    }

    private func pushNowPlayingInfo() {
        guard let current = player.current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist,
            MPMediaItemPropertyAlbumTitle: current.album,
            MPMediaItemPropertyPlaybackDuration: current.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0,
        ]
        if let artwork = artwork(for: current.artworkID) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func artwork(for artworkID: String?) -> MPMediaItemArtwork? {
        guard let artworkID, let artworkDirectory else { return nil }
        if let cachedArtwork, cachedArtwork.id == artworkID {
            return cachedArtwork.artwork
        }

        let url = artworkDirectory.appendingPathComponent("\(artworkID).img")
        guard let data = try? Data(contentsOf: url) else { return nil }

        #if canImport(UIKit)
            guard let image = UIImage(data: data) else { return nil }
            let mediaArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        #elseif canImport(AppKit)
            guard let image = NSImage(data: data) else { return nil }
            let mediaArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        #else
            return nil
        #endif

        cachedArtwork = (artworkID, mediaArtwork)
        return mediaArtwork
    }
}
