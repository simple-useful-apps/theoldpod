import DesignSystem
import PlaybackEngine
import SwiftUI

/// The full "what's playing" surface: artwork, title/artist/album, the shared
/// scrubber, and the full transport (shuffle, previous, play/pause, next,
/// repeat). Works standalone — iOS presents it as a sheet, macOS reuses it in
/// a mini-player window.
public struct NowPlayingView: View {
    private let player: PlayerController
    private let artworkDirectory: URL?
    @State private var isUpNextPresented = false

    public init(player: PlayerController, artworkDirectory: URL?) {
        self.player = player
        self.artworkDirectory = artworkDirectory
    }

    public var body: some View {
        if let current = player.current {
            VStack(spacing: 24) {
                ArtworkImage(
                    artworkID: current.artworkID,
                    directory: artworkDirectory,
                    cornerRadius: 16,
                    pointSize: 320,
                    placeholderSystemName: current.bookID != nil ? "book.closed" : "music.note"
                )
                .frame(maxWidth: 320)
                .padding(.top, 24)

                VStack(spacing: 4) {
                    Text(current.title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .accessibilityIdentifier("nowPlayingTitle")
                    // A skipped, unplayable file briefly replaces the subtitle.
                    Text(player.unplayableNotice ?? current.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .accessibilityIdentifier("nowPlayingSubtitle")
                }
                .padding(.horizontal, 24)

                ScrubberView(player: player)
                    .padding(.horizontal, 24)

                transportRow
                    .padding(.horizontal, 24)

                if current.bookID != nil {
                    ListeningControls(player: player, isProminent: true)
                        .padding(.horizontal, 24)
                }

                Spacer(minLength: 0)

                #if os(iOS)
                    systemControls
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                #endif
            }
            #if os(iOS)
            .sheet(isPresented: $isUpNextPresented) {
                NavigationStack {
                    UpNextView(player: player)
                }
                .presentationDetents([.medium, .large])
            }
            #endif
        } else {
            VStack(spacing: 12) {
                ArtworkPlaceholder(cornerRadius: 16)
                    .frame(maxWidth: 320)
                Text("Not Playing")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    #if os(iOS)
        /// Volume, output route and the queue — the bottom of the screen,
        /// within thumb reach.
        private var systemControls: some View {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    SystemVolumeSlider()
                        .frame(height: 34)
                        .accessibilityLabel("Volume")
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                HStack {
                    Spacer()
                    AudioRoutePicker()
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("AirPlay")
                    Spacer()
                    Button {
                        isUpNextPresented = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .imageScale(.large)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("nowPlayingUpNextButton")
                    .accessibilityLabel("Up Next")
                    Spacer()
                }
            }
        }
    #endif

    private var transportRow: some View {
        let isBook = player.current?.bookID != nil
        return HStack(spacing: 28) {
            // Shuffle and repeat don't apply to a book's chapters.
            if !isBook {
                ShuffleToggle(player: player)
            }

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
            }
            .accessibilityIdentifier("nowPlayingPreviousButton")
            .accessibilityLabel("Previous Track")

            Button {
                player.togglePlayPause()
            } label: {
                PlayPauseSymbol(isPlaying: player.isPlaying)
                    .font(.system(size: 44))
                    .frame(width: 52)
            }
            .accessibilityIdentifier("nowPlayingPlayPauseButton")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
            }
            .accessibilityIdentifier("nowPlayingNextButton")
            .accessibilityLabel("Next Track")

            if !isBook {
                RepeatToggle(player: player)
            }
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
        .disabled(player.current == nil)
    }
}
