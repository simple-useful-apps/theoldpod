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
    @State private var importing = false
    @State private var importError: String?
    @State private var importProgress: ImportProgress?
    @State private var searchText = ""
    @State private var deletionRequest: LibraryDeletionRequest?

    public init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }

    private var bookNames: [String] {
        Array(Set(tracks.compactMap(\.bookID))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public var body: some View {
        Group {
            if bookNames.isEmpty {
                ContentUnavailableView {
                    Label("No Books Yet", systemImage: "book.closed")
                } description: {
                    Text("Import a book folder or select its chapter files. Each book keeps its own listening position.")
                } actions: {
                    Button("Import Book") { title = ""; namingBook = true }
                        .disabled(importing)
                }
            } else {
                List(bookNames.filter { searchText.isEmpty || $0.localizedStandardContains(searchText) }, id: \.self) { name in
                    NavigationLink {
                        BookDetailView(name: name, coordinator: coordinator)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "book.closed")
                                .font(.title2).frame(width: 40, height: 48)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name)
                                let chapters = tracks.filter { $0.bookID == name }
                                Text(bookSummary(chapters))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contextMenu {
                        Button("Delete Book…", systemImage: "trash", role: .destructive) {
                            deletionRequest = .book(name: name)
                        }
                    }
                    #if os(iOS)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            deletionRequest = .book(name: name)
                        } label: {
                            Label("Delete Book", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                    #endif
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Books")
        .searchable(text: $searchText, prompt: "Search Books")
        .overlay {
            if !bookNames.isEmpty, !searchText.isEmpty, !bookNames.contains(where: { $0.localizedStandardContains(searchText) }) {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .refreshable { await coordinator.refreshLibrary() }
        .toolbar {
            #if os(iOS)
                ToolbarItem(placement: .automatic) { LibraryStatusButton(coordinator: coordinator) }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button {
                    title = ""; namingBook = true
                } label: {
                    Label(importing ? "Importing…" : "Import Book", systemImage: "plus")
                }
                .disabled(importing)
            }
            if let progress = importProgress {
                ToolbarItem(placement: .automatic) {
                    Text("\(progress.description) (\(progress.completed) of \(progress.total))")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .alert("Import Book", isPresented: $namingBook) {
            TextField("Book title", text: $title)
            Button("Choose Chapters") { pickingFiles = true }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Name the book, then select its folder or all its chapter files. Originals are left unchanged.")
        }
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: ImportService.supportedContentTypes, allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result, !importing else { return }
            importing = true
            let bookTitle = title
            Task {
                let result = await ImportService(libraryRoot: coordinator.libraryRoot).importAudiobook(at: urls, title: bookTitle) { progress in
                    importProgress = progress
                }
                importing = false
                importProgress = nil
                importError = result.report
            }
        }
        .alert("Book Import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(importError ?? "") }
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
        tracks.filter { $0.bookID == name }.sorted {
            // Filename prefixes are authoritative for untagged Manning books.
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    var body: some View {
        let chapters = chapters
        let progress = coordinator.player.bookProgress(name)
        List {
            Section {
                if let state = coordinator.bookPreparation[name] {
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
                                Task { await coordinator.prepareBook(named: name, relativePaths: chapters.map(\.relativePath)) }
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
        .listStyle(.plain)
        .navigationTitle(name)
        .task(id: chapters.map(\.relativePath)) {
            await coordinator.prepareBook(named: name, relativePaths: chapters.map(\.relativePath))
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
