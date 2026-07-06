#if os(iOS)
    import SwiftUI

    /// The iOS shell: Artists / Albums / Songs / Playlists tabs, each its own
    /// `NavigationStack`, with the persistent mini-player docked above the tab
    /// bar via iOS 26's `tabViewBottomAccessory`. Tapping the mini-player
    /// presents the full `NowPlayingView` as a large-detent sheet.
    public struct RootTabView: View {
        private let coordinator: LibraryCoordinator

        @State private var selection: RootTab = .songs
        @State private var isNowPlayingPresented = false

        public init(coordinator: LibraryCoordinator) {
            self.coordinator = coordinator
        }

        public var body: some View {
            TabView(selection: $selection) {
                Tab("Artists", systemImage: "music.mic", value: RootTab.artists) {
                    NavigationStack {
                        ArtistsListView(coordinator: coordinator)
                            .navigationTitle("Artists")
                    }
                }

                Tab("Albums", systemImage: "square.stack", value: RootTab.albums) {
                    NavigationStack {
                        AlbumsGridView(coordinator: coordinator)
                            .navigationTitle("Albums")
                    }
                }

                Tab("Songs", systemImage: "music.note.list", value: RootTab.songs) {
                    NavigationStack {
                        SongsListView(coordinator: coordinator)
                            .navigationTitle("Songs")
                    }
                }

                Tab("Playlists", systemImage: "list.bullet", value: RootTab.playlists) {
                    NavigationStack {
                        PlaylistsListView(coordinator: coordinator)
                            .navigationTitle("Playlists")
                    }
                }
            }
            .tabViewBottomAccessory {
                MiniPlayerBar(player: coordinator.player, artworkDirectory: coordinator.artworkDirectory)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isNowPlayingPresented = true
                    }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .sheet(isPresented: $isNowPlayingPresented) {
                NowPlayingView(player: coordinator.player, artworkDirectory: coordinator.artworkDirectory)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .task {
                coordinator.start()
            }
        }
    }

    private enum RootTab: Hashable {
        case artists, albums, songs, playlists
    }
#endif
