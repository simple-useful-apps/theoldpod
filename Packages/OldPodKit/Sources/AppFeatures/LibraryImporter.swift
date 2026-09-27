import CloudFiles
import Foundation
import Observation
import SwiftUI

/// Runs library imports and exposes their progress and outcome, so every
/// import entry point (toolbar button, drag and drop, book import) shares one
/// progress indicator and one report alert on both platforms.
@MainActor
@Observable
public final class LibraryImporter {
    public private(set) var isImporting = false
    public private(set) var progress: ImportProgress?
    public var report: String?

    private let libraryRoot: URL
    private let refreshLibrary: () async -> Void

    init(libraryRoot: URL, refreshLibrary: @escaping () async -> Void) {
        self.libraryRoot = libraryRoot
        self.refreshLibrary = refreshLibrary
    }

    public func importFiles(at urls: [URL]) {
        run { service, onProgress in
            await service.importFiles(at: urls, onProgress: onProgress)
        }
    }

    public func importAudiobook(at urls: [URL], title: String) {
        run { service, onProgress in
            await service.importAudiobook(at: urls, title: title, onProgress: onProgress)
        }
    }

    private func run(
        _ body: @escaping (ImportService, @escaping @MainActor @Sendable (ImportProgress) -> Void) async -> ImportResult
    ) {
        guard !isImporting else { return }
        isImporting = true
        Task {
            let result = await body(ImportService(libraryRoot: libraryRoot)) { [weak self] in
                self?.progress = $0
            }
            if !result.imported.isEmpty {
                await refreshLibrary()
            }
            isImporting = false
            progress = nil
            report = result.report
        }
    }
}

/// "Copying song.mp3 (3 of 12)" while an import runs; nothing otherwise.
public struct ImportProgressLabel: View {
    private let importer: LibraryImporter

    public init(_ importer: LibraryImporter) {
        self.importer = importer
    }

    public var body: some View {
        if let progress = importer.progress {
            Text("\(progress.description) (\(progress.completed) of \(progress.total))")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

public extension View {
    /// Shows the importer's report once an import finishes with issues.
    func importReportAlert(_ importer: LibraryImporter) -> some View {
        modifier(ImportReportAlert(importer: importer))
    }
}

private struct ImportReportAlert: ViewModifier {
    @Bindable var importer: LibraryImporter

    func body(content: Content) -> some View {
        content.alert(
            "Import Finished with Issues",
            isPresented: $importer.report.isPresent,
            presenting: importer.report
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { report in
            Text(report)
        }
    }
}
