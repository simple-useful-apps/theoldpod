import AppFeatures
import CloudFiles
import SwiftUI

struct MetadataEditorPresentation: Identifiable {
    let relativePath: String

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
/// people most often changed in classic iTunes, without turning this into a
/// full tag-inspection utility.
struct MetadataEditorView: View {
    let relativePath: String
    let coordinator: LibraryCoordinator

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var albumArtist = ""
    @State private var genre = ""
    @State private var year = ""
    @State private var trackNumber = ""
    @State private var trackTotal: Int?
    @State private var discNumber = ""
    @State private var discTotal: Int?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var didLoad = false
    @State private var versionToken: AudioMetadataVersionToken?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Song Info")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text((relativePath as NSString).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(relativePath)
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
                        TextField("", text: $trackNumber)
                            .frame(width: 58)
                        Text("Disc")
                            .foregroundStyle(.secondary)
                        TextField("", text: $discNumber)
                            .frame(width: 58)
                    }
                }
                .textFieldStyle(.roundedBorder)
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
        .frame(width: 520)
        .interactiveDismissDisabled(isSaving)
        .task { await load() }
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
            trackTotal = fields.trackTotal
            discNumber = fields.discNumber.map(String.init) ?? ""
            discTotal = fields.discTotal
            versionToken = session.version
            didLoad = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func save() {
        errorMessage = nil
        guard let versionToken, didLoad else { return }
        guard let year = number(year, named: "year"),
              let trackNumber = number(trackNumber, named: "track number"),
              let discNumber = number(discNumber, named: "disc number")
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
