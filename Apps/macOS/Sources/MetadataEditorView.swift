import AppFeatures
import AppKit
import AVFoundation
import CloudFiles
import DesignSystem
import SwiftUI

struct MetadataEditorPresentation: Identifiable {
    let relativePath: String
    let artworkID: String?
    /// The indexed duration (read once at import).
    let duration: TimeInterval

    var id: String {
        relativePath
    }
}

struct GetInfoActionKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}

extension FocusedValues {
    var getInfoAction: GetInfoActionKey.Value? {
        get { self[GetInfoActionKey.self] }
        set { self[GetInfoActionKey.self] = newValue }
    }
}

/// A deliberately compact, native Mac sheet: the eight ordinary music tags
/// people most often changed in classic iTunes (plus track/disc totals), the
/// artwork (choose, drop, or remove), and a few read-only file facts —
/// without turning this into a full tag-inspection utility.
struct MetadataEditorView: View {
    let request: MetadataEditorPresentation
    let coordinator: LibraryCoordinator

    private var relativePath: String {
        request.relativePath
    }

    private var fileURL: URL {
        coordinator.libraryRoot.appendingPathComponent(relativePath)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var albumArtist = ""
    @State private var genre = ""
    @State private var year = ""
    @State private var trackNumber = ""
    @State private var trackTotal = ""
    @State private var discNumber = ""
    @State private var discTotal = ""
    @State private var details: AudioFileDetails?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var didLoad = false
    @State private var versionToken: AudioMetadataVersionToken?
    @State private var errorMessage: String?
    @State private var artworkChange: AudioArtworkChange = .keep

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                artworkWell
                VStack(alignment: .leading, spacing: 3) {
                    Text("Song Info")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text((relativePath as NSString).lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(relativePath)
                    HStack(spacing: 6) {
                        Button("Choose Artwork\u{2026}") { chooseArtwork() }
                        Button("Remove Artwork") { artworkChange = .remove }
                            .disabled(!hasArtwork)
                    }
                    .controlSize(.small)
                    .disabled(!didLoad || isSaving)
                    .padding(.top, 3)
                }
            }

            if isLoading {
                ProgressView("Reading file information…")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                    metadataRow("Title", text: $title)
                    metadataRow("Artist", text: $artist)
                    metadataRow("Album", text: $album)
                    metadataRow("Album Artist", text: $albumArtist)
                    metadataRow("Genre", text: $genre)
                    GridRow {
                        Text("Year")
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        TextField("", text: $year)
                            .frame(width: 90)
                        Text("Track")
                            .foregroundStyle(.secondary)
                        numberOfTotal(number: $trackNumber, total: $trackTotal, name: "Track")
                        Text("Disc")
                            .foregroundStyle(.secondary)
                        numberOfTotal(number: $discNumber, total: $discTotal, name: "Disc")
                    }
                }
                .textFieldStyle(.roundedBorder)

                Divider()

                detailsGrid
            }

            if let errorMessage {
                HStack(alignment: .firstTextBaseline) {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    if !didLoad, !isLoading {
                        Spacer()
                        Button("Retry") { Task { await load() } }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isLoading || isSaving || !didLoad || versionToken == nil)
            }
        }
        .padding(20)
        .frame(width: 560)
        .interactiveDismissDisabled(isSaving)
        .task { await load() }
    }

    /// The artwork Save will write: the file's own until a picture is chosen,
    /// dropped, or removed. Dropping an image here works like iTunes did.
    private var artworkWell: some View {
        Group {
            if case let .replace(data) = artworkChange, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ArtworkImage(
                    artworkID: artworkChange == .remove ? nil : request.artworkID,
                    directory: coordinator.artworkDirectory,
                    cornerRadius: 8,
                    pointSize: 72
                )
            }
        }
        .frame(width: 72, height: 72)
        .accessibilityLabel("Artwork")
        .dropDestination(for: URL.self) { urls, _ in
            guard didLoad, !isSaving, let url = urls.first else { return false }
            useArtwork(at: url)
            return true
        }
    }

    private var hasArtwork: Bool {
        switch artworkChange {
        case .keep: request.artworkID != nil
        case .replace: true
        case .remove: false
        }
    }

    private func chooseArtwork() {
        Task {
            guard let url = await ArtworkPicker.chooseImage() else { return }
            useArtwork(at: url)
        }
    }

    private func useArtwork(at url: URL) {
        errorMessage = nil
        Task {
            do {
                let data = try await Task.detached { try ArtworkImagePreparer.jpegData(contentsOf: url) }.value
                artworkChange = .replace(data)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// "[ 3 ] of [ 12 ]" — the classic iTunes track/disc pair.
    private func numberOfTotal(number: Binding<String>, total: Binding<String>, name: String) -> some View {
        HStack(spacing: 4) {
            TextField("", text: number)
                .frame(width: 44)
                .accessibilityLabel(name)
            Text("of")
                .foregroundStyle(.secondary)
                // The grid squeezed it to "o'" between the fixed-width fields.
                .fixedSize()
            TextField("", text: total)
                .frame(width: 44)
                .accessibilityLabel("\(name) Total")
        }
    }

    /// Read-only facts about the file itself.
    private var detailsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            detailRow("Kind", details?.kind ?? "\u{2014}")
            detailRow("Duration", DurationText.format(request.duration), monospaced: true)
            detailRow("Size", details?.fileSize.map {
                ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
            } ?? "\u{2014}")
            detailRow("Bit Rate", details?.kilobitsPerSecond.map { "\($0) kbps" } ?? "\u{2014}")
            GridRow(alignment: .firstTextBaseline) {
                Text("Location")
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                HStack(alignment: .firstTextBaseline) {
                    Text(fileURL.path)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(fileURL.path)
                    Spacer(minLength: 8)
                    Button("Show in Finder") {
                        FinderReveal.reveal(fileURL)
                    }
                    .controlSize(.small)
                }
            }
        }
        .font(.callout)
    }

    private func detailRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(monospaced ? OldPodTypography.timeReadout() : .callout)
                .textSelection(.enabled)
        }
    }

    private func metadataRow(_ label: String, text: Binding<String>) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
                .fixedSize()
            TextField("", text: text)
                .gridCellColumns(5)
        }
    }

    private func load() async {
        isLoading = true
        didLoad = false
        versionToken = nil
        errorMessage = nil
        do {
            let session = try await coordinator.metadataEditSession(for: relativePath)
            let fields = session.fields
            title = fields.title ?? ""
            artist = fields.artist ?? ""
            album = fields.album ?? ""
            albumArtist = fields.albumArtist ?? ""
            genre = fields.genre ?? ""
            year = fields.year.map(String.init) ?? ""
            trackNumber = fields.trackNumber.map(String.init) ?? ""
            trackTotal = fields.trackTotal.map(String.init) ?? ""
            discNumber = fields.discNumber.map(String.init) ?? ""
            discTotal = fields.discTotal.map(String.init) ?? ""
            versionToken = session.version
            didLoad = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        if details == nil {
            details = await AudioFileDetails.read(url: fileURL, duration: request.duration)
        }
    }

    private func save() {
        errorMessage = nil
        guard let versionToken, didLoad else { return }
        guard let year = number(year, named: "year"),
              let trackNumber = number(trackNumber, named: "track number"),
              let trackTotal = number(trackTotal, named: "track total"),
              let discNumber = number(discNumber, named: "disc number"),
              let discTotal = number(discTotal, named: "disc total")
        else { return }

        let fields = AudioMetadataFields(
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            genre: genre,
            year: year,
            trackNumber: trackNumber,
            trackTotal: trackNumber == nil ? nil : trackTotal,
            discNumber: discNumber,
            discTotal: discNumber == nil ? nil : discTotal
        )
        isSaving = true
        Task {
            do {
                _ = try await coordinator.updateMetadata(
                    relativePath: relativePath,
                    fields: fields,
                    artwork: artworkChange,
                    expectedVersion: versionToken
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    /// `nil` is both a valid cleared field and an invalid parse result, so
    /// this helper reports bad input through `errorMessage` before returning.
    private func number(_ raw: String, named name: String) -> Int?? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .some(nil) }
        guard let value = Int(trimmed), (1 ... 9999).contains(value) else {
            errorMessage = "Enter a valid \(name) from 1 to 9999, or leave it blank."
            return nil
        }
        return .some(value)
    }
}

/// Read-only file facts for Get Info: kind, size, and average bit rate.
struct AudioFileDetails: Equatable {
    let kind: String
    let fileSize: Int64?
    let kilobitsPerSecond: Int?

    /// Reads the size from the file system and the codec/data rate from the
    /// first audio track, falling back to size ÷ indexed duration.
    static func read(url: URL, duration: TimeInterval) async -> AudioFileDetails {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        var subtype: FourCharCode?
        var dataRate: Float?
        if let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first {
            if let format = try? await track.load(.formatDescriptions).first {
                subtype = CMFormatDescriptionGetMediaSubType(format)
            }
            dataRate = try? await track.load(.estimatedDataRate)
        }
        var kbps: Int?
        if let dataRate, dataRate > 0 {
            kbps = Int((dataRate / 1000).rounded())
        } else if let size, duration > 0 {
            kbps = Int((Double(size) * 8 / duration / 1000).rounded())
        }
        return AudioFileDetails(
            kind: kindDescription(pathExtension: url.pathExtension, subtype: subtype),
            fileSize: size,
            kilobitsPerSecond: kbps
        )
    }

    static func kindDescription(pathExtension: String, subtype: FourCharCode?) -> String {
        switch subtype {
        case kAudioFormatMPEGLayer3: "MP3 audio file"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2: "AAC audio file"
        case kAudioFormatAppleLossless: "Apple Lossless audio file"
        default:
            switch pathExtension.lowercased() {
            case "mp3": "MP3 audio file"
            case "m4a": "AAC audio file"
            default: "Audio file"
            }
        }
    }
}
