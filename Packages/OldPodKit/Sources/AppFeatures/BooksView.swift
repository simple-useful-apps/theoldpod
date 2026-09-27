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
                    NavigationLink {
                        BookDetailView(name: name, coordinator: coordinator)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "book.closed")
                                .font(.title2).frame(width: 40, height: 48)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name)
                                Text(bookSummary(chaptersByBook[name] ?? []))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contextMenu {
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
    }

    private func bookSummary(_ chapters: [Track]) -> String {
        let count = "\(chapters.count) chapter\(chapters.count == 1 ? "" : "s")"
        guard chapters.allSatisfy({ $0.duration > 0 }) else { return count }
        return "\(count) · \(DurationText.format(chapters.reduce(0) { $0 + $1.duration }))"
    }
}

private struct BookDetailView: View {
    let name: String
    let coordinator: LibraryCoordinator
    @Query private var tracks: [Track]
    @Environment(\.dismiss) private var dismiss
    @State private var deletionRequest: LibraryDeletionRequest?

    private var chapters: [Track] {
        // Chapters sort by filename, not tag: untagged downloads still read in order.
        tracks.filter { $0.bookID == name }.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    var body: some View {
        let chapters = chapters
        let progress = coordinator.player.bookProgress(name)
        List {
            Section {
                if let state = coordinator.books.states[name] {
                    switch state {
                    case let .preparing(completed, total):
                        HStack {
                            ProgressView()
                            Text("Preparing chapters… \(completed) of \(total)")
                                .foregroundStyle(.secondary)
                        }
                    case .ready:
                        EmptyView()
                    case let .failed(message):
                        VStack(alignment: .leading, spacing: 8) {
                            Text(message).foregroundStyle(.secondary)
                            Button("Try Again") {
                                Task { await coordinator.books.prepare(named: name, relativePaths: chapters.map(\.relativePath)) }
                            }
                        }
                    }
                }
                Button {
                    coordinator.player.resumeBook(coordinator.playableTracks(from: chapters))
                } label: {
                    HStack {
                        Text(progress?.finished == true ? "Listen Again" : (progress == nil ? "Listen" : "Resume"))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(chapters.isEmpty)
                if let progress, !progress.finished,
                   let chapter = chapters.first(where: { $0.relativePath == progress.path })
                {
                    Text("\(chapter.title) · \(DurationText.format(progress.seconds))")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                        HStack {
                            Text(chapter.title).foregroundStyle(.primary)
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
        .task(id: chapters.map(\.relativePath)) {
            await coordinator.books.prepare(named: name, relativePaths: chapters.map(\.relativePath))
        }
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
