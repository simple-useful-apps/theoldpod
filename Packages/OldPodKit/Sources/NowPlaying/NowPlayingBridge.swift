import Foundation
import ImageIO
import MediaPlayer
import MetadataImport
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
        pushNowPlayingInfo()
    }

    private func registerCommandHandlers() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = PlayerController.supportedSpeeds.map { NSNumber(value: $0) }
        commandCenter.skipBackwardCommand.addTarget { [player] _ in
            guard player.current != nil else { return .noSuchContent }
            player.skip(by: -15)
            return .success
        }
        commandCenter.skipForwardCommand.addTarget { [player] _ in
            guard player.current != nil else { return .noSuchContent }
            player.skip(by: 15)
            return .success
        }
        commandCenter.changePlaybackRateCommand.addTarget { [player] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            player.setSpeed(event.playbackRate)
            return .success
        }

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

    /// Re-arming observation over the discontinuity signals only (track,
    /// play state, seeks), never `currentTime`: the system extrapolates
    /// elapsed time from the rate and one timestamp, so pushing the info
    /// dictionary on every half-second tick would be wasted XPC traffic.
    /// `pushNowPlayingInfo()` reads `currentTime` outside the tracked scope.
    private func scheduleNowPlayingInfoUpdate() {
        guard isActive else { return }
        withObservationTracking {
            _ = player.current
            _ = player.isPlaying
            _ = player.seekCount
            _ = player.playbackSpeed
            _ = player.currentDuration
            _ = player.canSeek
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.pushNowPlayingInfo()
                self.scheduleNowPlayingInfoUpdate()
            }
        }
    }

    private func pushNowPlayingInfo() {
        let commands = MPRemoteCommandCenter.shared()
        let isBook = player.current?.bookID != nil
        commands.skipBackwardCommand.isEnabled = isBook && player.canSeek
        commands.skipForwardCommand.isEnabled = isBook && player.canSeek
        commands.changePlaybackRateCommand.isEnabled = isBook
        commands.changePlaybackPositionCommand.isEnabled = player.canSeek
        commands.nextTrackCommand.isEnabled = !isBook
        commands.previousTrackCommand.isEnabled = !isBook
        guard let current = player.current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist,
            MPMediaItemPropertyAlbumTitle: current.album,
            MPMediaItemPropertyPlaybackDuration: player.currentDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? player.playbackSpeed : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: player.playbackSpeed,
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

        let url = ArtworkStore.fileURL(for: artworkID, in: artworkDirectory)
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let size = CGSize(width: cgImage.width, height: cgImage.height)
        // MediaPlayer invokes this handler on its own private dispatch queue.
        // A plain closure formed here would inherit this class's @MainActor
        // isolation and Swift 6's runtime isolation check would trap
        // (dispatch_assert_queue_fail → SIGTRAP) the moment now-playing info
        // is pushed for a track with artwork. It must be @Sendable
        // (nonisolated) and capture only Sendable values — CGImage is
        // immutable; the platform image is wrapped per invocation.
        let mediaArtwork = MPMediaItemArtwork(boundsSize: size) { @Sendable _ in
            #if canImport(UIKit)
                UIImage(cgImage: cgImage)
            #else
                NSImage(cgImage: cgImage, size: size)
            #endif
        }

        cachedArtwork = (artworkID, mediaArtwork)
        return mediaArtwork
    }
}
