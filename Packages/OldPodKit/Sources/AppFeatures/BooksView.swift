import CloudFiles
import DesignSystem
import Domain
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A book is a folder of chapters, so even untagged downloads stay separate.
public struct BooksView: View {
    private let coordinator: LibraryCoordinator
    @Query private var tracks: [Track]
    @State private var namingBook = false
    @State private var pickingFiles = false
    @State private var title = ""
    @State private var searchText = ""
    @State private var deletionRequest: LibraryDeletionRequest?
    #if os(macOS)
        @State private var artworkRequest: ArtworkRequest?
    #endif

    public init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        let chaptersByBook = Dictionary(grouping: tracks.filter(\.isAudiobook)) { $0.bookID ?? "" }
        let bookNames = chaptersByBook.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let filtered = bookNames.filter { searchText.isEmpty || $0.localizedStandardContains(searchText) }
        Group {
            if bookNames.isEmpty {
                ContentUnavailableView {
                    Label("No Books Yet", systemImage: "book.closed")
                } description: {
                    Text("Import a book folder or select its chapter files. Each book keeps its own listening position.")
                } actions: {
                    Button("Import Book") { title = ""; namingBook = true }
                        .disabled(coordinator.importer.isImporting)
                }
            } else {
                List(filtered, id: \.self) { name in
                    let chapters = BookChapters.sorted(chaptersByBook[name] ?? [])
                    NavigationLink {
                        BookDetailView(name: name, coordinator: coordinator)
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkImage(
                                artworkID: chapters.lazy.compactMap(\.artworkID).first,
                                directory: coordinator.artworkDirectory,
                                pointSize: 48,
                                placeholderSystemName: "book.closed"
                            )
                            .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name)
                                    .lineLimit(2)
                                Text(bookSummary(chapters))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .contextMenu {
                        #if os(macOS)
                            ArtworkMenuItems(title: name, tracks: chapters, request: $artworkRequest)
                            Divider()
                        #endif
                        Button("Delete Book…", systemImage: "trash", role: .destructive) {
                            deletionRequest = .book(name: name)
                        }
                    }
                    .deleteSwipeAction("Delete Book") { deletionRequest = .book(name: name) }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Books")
        .searchable(text: $searchText, prompt: "Search Books")
        .searchEmptyOverlay(isEmpty: !bookNames.isEmpty && filtered.isEmpty, searchText: searchText)
        .refreshable { await coordinator.refreshLibrary() }
        .toolbar {
            #if os(iOS)
                ToolbarItem(placement: .automatic) { LibraryStatusButton(coordinator: coordinator) }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button {
                    title = ""; namingBook = true
                } label: {
                    Label(coordinator.importer.isImporting ? "Importing…" : "Import Book", systemImage: "plus")
                }
                .disabled(coordinator.importer.isImporting)
            }
            ToolbarItem(placement: .automatic) { ImportProgressLabel(coordinator.importer) }
        }
        .alert("Import Book", isPresented: $namingBook) {
            TextField("Book title", text: $title)
            Button("Choose Chapters") { pickingFiles = true }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Name the book, then select its folder or all its chapter files. Originals are left unchanged.")
        }
        .fileImporter(
            isPresented: $pickingFiles,
            allowedContentTypes: ImportService.supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                coordinator.importer.importAudiobook(at: urls, title: title)
            }
        }
        .importReportAlert(coordinator.importer)
        .libraryDeletionConfirmation(request: $deletionRequest, coordinator: coordinator)
        #if os(macOS)
            .artworkRequests($artworkRequest, coordinator: coordinator)
        #endif
    }

    /// "Author · N chapters · h:mm:ss" — author and duration only when known.
    private func bookSummary(_ chapters: [Track]) -> String {
        var parts: [String] = []
        if let author = BookChapters.author(of: chapters) { parts.append(author) }
        parts.append(LibraryText.chapterCount(chapters.count))
        if let total = BookChapters.totalDuration(of: chapters) { parts.append(DurationText.format(total)) }
        return parts.joined(separator: " · ")
    }
}

/// Shared chapter ordering and summaries for the book list and book page.
private enum BookChapters {
    /// Chapters sort by filename, not tag: untagged downloads still read in order.
    static func sorted(_ chapters: [Track]) -> [Track] {
        chapters.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    /// The first non-empty track artist among the chapters, if any.
    static func author(of chapters: [Track]) -> String? {
        chapters.lazy
            .map { $0.artist.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// The book's length, or nil while any chapter's duration is unknown.
    static func totalDuration(of chapters: [Track]) -> TimeInterval? {
        guard !chapters.isEmpty, chapters.allSatisfy({ $0.duration > 0 }) else { return nil }
        return chapters.reduce(0) { $0 + $1.duration }
    }
}

private struct BookDetailView: View {
    let name: String
    let coordinator: LibraryCoordinator
    @Query private var tracks: [Track]
    @Environment(\.dismiss) private var dismiss
    @State private var deletionRequest: LibraryDeletionRequest?

    private var chapters: [Track] {
        BookChapters.sorted(tracks.filter { $0.bookID == name })
    }

    /// Where the listener is in this book: live from the player while one of
    /// its chapters is loaded, otherwise the saved bookmark.
    private func position(in chapters: [Track]) -> (path: String, seconds: Double, finished: Bool)? {
        if let current = coordinator.player.current?.relativePath,
           chapters.contains(where: { $0.relativePath == current })
        {
            return (current, coordinator.player.currentTime, false)
        }
        return coordinator.player.bookProgress(name)
    }

    var body: some View {
        let chapters = chapters
        let progress = position(in: chapters)
        let playingPath = coordinator.player.current?.relativePath
        List {
            Section {
                // Chapters are prepared in the background as soon as the
                // book is indexed; this screen only surfaces a failure.
                if case let .failed(message) = coordinator.books.states[name] {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message).foregroundStyle(.secondary)
                        Button("Try Again") {
                            coordinator.books.prepareIncompleteBooks(among: [name])
                        }
                    }
                }
                Button {
                    coordinator.player.resumeBook(coordinator.playableTracks(from: chapters))
                } label: {
                    Label(
                        progress?.finished == true ? "Listen Again" : (progress == nil ? "Listen" : "Resume"),
                        systemImage: "play.fill"
                    )
                    .labelStyle(.titleAndIcon)
                    #if os(iOS)
                        .frame(maxWidth: .infinity)
                    #endif
                }
                .buttonStyle(.borderedProminent)
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("bookListenButton")
                .disabled(chapters.isEmpty)
                // Always present, so starting the book doesn't push the
                // chapter list down under the listener's next tap.
                BookProgressSummary(chapters: chapters, progress: progress)
                if coordinator.player.progressSaveFailed {
                    Text("Listening progress couldn't be saved. Check available storage.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let notice = coordinator.player.playbackNotice {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Chapters") {
                ForEach(Array(chapters.enumerated()), id: \.element.persistentModelID) { index, chapter in
                    Button {
                        coordinator.play(chapters, startingAt: index)
                    } label: {
                        HStack(spacing: 12) {
                            Group {
                                if chapter.relativePath == playingPath {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(.tint)
                                        .accessibilityLabel("Now Playing")
                                } else {
                                    Text("\(index + 1)")
                                        .font(OldPodTypography.timeReadout())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 24, alignment: .trailing)
                            Text(chapter.title)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer()
                            if chapter.duration > 0 {
                                DurationText(chapter.duration).foregroundStyle(.secondary)
                            } else {
                                Text("—").foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        #if os(macOS)
        // Plain on the Mac runs rows flush against the sidebar edge.
        .listStyle(.inset)
        #else
        .listStyle(.plain)
        #endif
        .navigationTitle(name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Delete Book…", systemImage: "trash", role: .destructive) {
                    deletionRequest = .book(name: name)
                }
            }
        }
        .libraryDeletionConfirmation(
            request: $deletionRequest,
            coordinator: coordinator
        ) { completion in
            // Keep this screen alive to show a post-delete refresh warning.
            if completion.bookWasDeleted, completion.result.postDeletionWarning == nil {
                dismiss()
            }
        }
    }
}

/// The book page's position line: a progress bar across the whole book and
/// "Chapter · 0:16 of 15:00" beside the book's length. Always the same
/// height, including before the first listen ("Not started").
private struct BookProgressSummary: View {
    let chapters: [Track]
    let progress: (path: String, seconds: Double, finished: Bool)?

    var body: some View {
        let total = BookChapters.totalDuration(of: chapters)
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: fraction(total: total))
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline) {
                Text(statusLine)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let total {
                    Text(DurationText.format(total))
                        .font(OldPodTypography.timeReadout())
                        .accessibilityLabel("Length \(DurationText.format(total))")
                }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusLine: String {
        guard let progress else { return "Not started" }
        if progress.finished { return "Finished" }
        guard let chapter = chapters.first(where: { $0.relativePath == progress.path }) else {
            return "Not started"
        }
        let position = DurationText.format(progress.seconds)
        guard chapter.duration > 0 else { return "\(chapter.title) · \(position)" }
        return "\(chapter.title) · \(position) of \(DurationText.format(chapter.duration))"
    }

    /// How far through the whole book the listener is, 0...1.
    private func fraction(total: TimeInterval?) -> Double {
        guard let progress else { return 0 }
        if progress.finished { return 1 }
        guard let total, total > 0,
              let index = chapters.firstIndex(where: { $0.relativePath == progress.path })
        else { return 0 }
        let before = chapters[..<index].reduce(0) { $0 + $1.duration }
        return min(max((before + progress.seconds) / total, 0), 1)
    }
}
