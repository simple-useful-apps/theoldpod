#if os(macOS)
    import AVFoundation
    import CoreMedia
    import Foundation
    import MetadataImport

    /// The ordinary music tags The Old Pod can edit. `nil` means remove the
    /// embedded value; it does not mean "leave the old value alone."
    public struct AudioMetadataFields: Sendable, Equatable {
        public var title: String?
        public var artist: String?
        public var album: String?
        public var albumArtist: String?
        public var genre: String?
        public var year: Int?
        public var trackNumber: Int?
        public var trackTotal: Int?
        public var discNumber: Int?
        public var discTotal: Int?

        public init(
            title: String? = nil,
            artist: String? = nil,
            album: String? = nil,
            albumArtist: String? = nil,
            genre: String? = nil,
            year: Int? = nil,
            trackNumber: Int? = nil,
            trackTotal: Int? = nil,
            discNumber: Int? = nil,
            discTotal: Int? = nil
        ) {
            self.title = title
            self.artist = artist
            self.album = album
            self.albumArtist = albumArtist
            self.genre = genre
            self.year = year
            self.trackNumber = trackNumber
            self.trackTotal = trackTotal
            self.discNumber = discNumber
            self.discTotal = discTotal
        }

        public init(metadata: TrackMetadata) {
            self.init(
                title: metadata.title,
                artist: metadata.artist,
                album: metadata.album,
                albumArtist: metadata.albumArtist,
                genre: metadata.genre,
                year: metadata.year,
                trackNumber: metadata.trackNumber,
                trackTotal: metadata.trackTotal,
                discNumber: metadata.discNumber,
                discTotal: metadata.discTotal
            )
        }

        fileprivate var normalized: Self {
            Self(
                title: Self.clean(title),
                artist: Self.clean(artist),
                album: Self.clean(album),
                albumArtist: Self.clean(albumArtist),
                genre: Self.clean(genre),
                year: year,
                trackNumber: trackNumber,
                trackTotal: trackTotal,
                discNumber: discNumber,
                discTotal: discTotal
            )
        }

        private static func clean(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return nil
            }
            return value
        }
    }

    /// What a rewrite does to a file's embedded picture. `replace` carries
    /// JPEG data, normally from `ArtworkImagePreparer`.
    public enum AudioArtworkChange: Sendable, Equatable {
        case keep
        case replace(Data)
        case remove

        fileprivate func expected(from original: Data?) -> Data? {
            switch self {
            case .keep: original
            case let .replace(data): data
            case .remove: nil
            }
        }
    }

    public enum AudioMetadataEditorError: LocalizedError, Sendable {
        case helperMissing
        case unsupportedFile
        case unavailableFile
        case invalidField(String)
        case fileChanged
        case rewriteFailed
        case validationFailed
        case replacementFailed

        public var errorDescription: String? {
            switch self {
            case .helperMissing:
                "The built-in metadata editor is unavailable. Reinstall The Old Pod."
            case .unsupportedFile:
                "Only downloaded MP3 and M4A music files can be edited."
            case .unavailableFile:
                "The file isn’t downloaded or is no longer available."
            case let .invalidField(field):
                "Enter a valid \(field)."
            case .fileChanged:
                "The file changed while its information was open. Reopen Get Info and try again."
            case .rewriteFailed:
                "The file’s metadata couldn’t be updated. The original file is unchanged."
            case .validationFailed:
                "The updated file didn’t pass audio validation. The original file is unchanged."
            case .replacementFailed:
                "The updated file couldn’t replace the original. The original file is unchanged."
            }
        }
    }

    /// Opaque identity for the exact file version read into a Get Info sheet.
    /// Callers can retain and return it, but cannot manufacture a token.
    public struct AudioMetadataVersionToken: Sendable, Equatable {
        fileprivate let version: FileVersion
    }

    public struct AudioMetadataEditSession: Sendable, Equatable {
        public let fields: AudioMetadataFields
        public let version: AudioMetadataVersionToken

        fileprivate init(fields: AudioMetadataFields, version: FileVersion) {
            self.fields = fields
            self.version = AudioMetadataVersionToken(version: version)
        }
    }

    /// Rewrites tags by stream-copying every audio stream and optional cover
    /// art through the bundled FFmpeg helper. The original file is replaced
    /// only after the candidate has been validated.
    public struct AudioMetadataEditor: Sendable {
        private let root: LibraryRoot

        public init(libraryRoot: URL) {
            root = LibraryRoot(url: libraryRoot)
        }

        /// Captures both the embedded values and the exact source version they
        /// came from. Save must return this token so a long-open sheet cannot
        /// overwrite a newer Finder/iCloud change with stale fields.
        public func load(relativePath: String) async throws -> AudioMetadataEditSession {
            let root = root
            return try await Task.detached {
                let source = try Self.editableFileURL(relativePath, in: root, allowsAudiobook: false)
                let before = try Self.version(of: source)
                let metadata = try await MetadataReader.read(from: source)
                guard try Self.version(of: source) == before else {
                    throw AudioMetadataEditorError.fileChanged
                }
                return AudioMetadataEditSession(fields: AudioMetadataFields(metadata: metadata), version: before)
            }.value
        }

        /// Returns `false` when the requested values already match the file,
        /// allowing callers to close an unchanged sheet without touching it.
        @discardableResult
        public func update(
            relativePath: String,
            fields: AudioMetadataFields,
            artwork: AudioArtworkChange = .keep,
            expectedVersion: AudioMetadataVersionToken
        ) async throws -> Bool {
            let root = root
            return try await Task.detached {
                let source = try Self.editableFileURL(relativePath, in: root, allowsAudiobook: false)
                let requested = try Self.validated(fields.normalized)
                return try await Self.rewrite(
                    source,
                    relativePath: relativePath,
                    in: root,
                    expectedVersion: expectedVersion.version,
                    requested: { _ in requested },
                    artwork: artwork
                )
            }.value
        }

        /// Sets or removes the embedded picture and leaves every other tag
        /// alone. Unlike `update`, this reads the file's version itself, so
        /// it suits applying one picture across an album or a book, and it
        /// accepts audiobook chapters. Returns `false` when nothing changed.
        @discardableResult
        public func updateArtwork(relativePath: String, to artwork: AudioArtworkChange) async throws -> Bool {
            let root = root
            return try await Task.detached {
                let source = try Self.editableFileURL(relativePath, in: root, allowsAudiobook: true)
                return try await Self.rewrite(
                    source,
                    relativePath: relativePath,
                    in: root,
                    expectedVersion: Self.version(of: source),
                    requested: { $0 },
                    artwork: artwork
                )
            }.value
        }

        /// Writes a validated candidate beside `source` and swaps it in.
        /// `requested` maps the file's current fields to the wanted ones.
        private static func rewrite(
            _ source: URL,
            relativePath: String,
            in root: LibraryRoot,
            expectedVersion: FileVersion,
            requested makeRequested: (AudioMetadataFields) -> AudioMetadataFields,
            artwork: AudioArtworkChange
        ) async throws -> Bool {
            let originalVersion = try version(of: source)
            guard originalVersion == expectedVersion else {
                throw AudioMetadataEditorError.fileChanged
            }
            let originalMetadata = try await MetadataReader.read(from: source)
            guard try version(of: source) == originalVersion else {
                throw AudioMetadataEditorError.fileChanged
            }
            let originalFields = AudioMetadataFields(metadata: originalMetadata).normalized
            let requested = makeRequested(originalFields)
            let expectedArtwork = artwork.expected(from: originalMetadata.artwork)
            guard originalFields != requested || expectedArtwork != originalMetadata.artwork else { return false }
            guard let helper = FFmpegHelper.url else { throw AudioMetadataEditorError.helperMissing }

            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("TheOldPod-Metadata-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

            let fileExtension = source.pathExtension.lowercased()
            let stagedInput = temporaryDirectory.appendingPathComponent("input.\(fileExtension)")
            // A hidden sibling with the real extension keeps the final
            // rename on one volume while still letting AVFoundation infer
            // the candidate's container during validation.
            let candidate = source.deletingLastPathComponent()
                .appendingPathComponent(".theoldpod-metadata-\(UUID().uuidString).\(fileExtension)")
            defer { try? FileManager.default.removeItem(at: candidate) }
            do {
                try FileManager.default.copyItem(at: source, to: stagedInput)
            } catch {
                throw AudioMetadataEditorError.unavailableFile
            }
            var stagedArtwork: URL?
            if case let .replace(data) = artwork, data != originalMetadata.artwork {
                // The helper's image2 demuxer picks its decoder by extension.
                let url = temporaryDirectory.appendingPathComponent("artwork.jpg")
                try data.write(to: url)
                stagedArtwork = url
            }

            let originalAudio = try await audioSignature(at: stagedInput)
            try await runHelper(
                helper,
                input: stagedInput,
                output: candidate,
                original: originalFields,
                requested: requested,
                artwork: stagedArtwork,
                removesArtwork: expectedArtwork == nil
            )
            try await validate(
                candidate,
                requested: requested,
                expectedArtwork: expectedArtwork,
                originalAudio: originalAudio
            )
            guard try version(of: source) == originalVersion else {
                throw AudioMetadataEditorError.fileChanged
            }
            try replace(source: source, with: candidate, relativePath: relativePath, root: root, originalVersion: originalVersion)
            return true
        }

        private struct AudioSignature: Equatable {
            let duration: TimeInterval
            let streamCount: Int
            let mediaSubtypes: [UInt32]
            let sampleRates: [Double]
            let channelCounts: [UInt32]
        }

        private static func editableFileURL(_ relativePath: String, in root: LibraryRoot, allowsAudiobook: Bool) throws -> URL {
            guard allowsAudiobook || !relativePath.hasPrefix("Audiobooks/"),
                  AudioFileSupport.supports(URL(fileURLWithPath: relativePath))
            else { throw AudioMetadataEditorError.unsupportedFile }
            guard let values = try root.inspect(relativePath) else { throw AudioMetadataEditorError.unavailableFile }
            guard values.isRegularFile == true else { throw AudioMetadataEditorError.unsupportedFile }
            return try root.resolve(relativePath)
        }

        private static func version(of url: URL) throws -> FileVersion {
            do {
                return try FileVersion(at: url)
            } catch {
                throw AudioMetadataEditorError.unavailableFile
            }
        }

        private static func validated(_ fields: AudioMetadataFields) throws -> AudioMetadataFields {
            for (name, value) in [
                ("title", fields.title), ("artist", fields.artist), ("album", fields.album),
                ("album artist", fields.albumArtist), ("genre", fields.genre),
            ] {
                guard let value else { continue }
                guard value.count <= 1024, !value.unicodeScalars.contains(where: { $0.value == 0 }) else {
                    throw AudioMetadataEditorError.invalidField(name)
                }
            }
            for (name, value) in [
                ("year", fields.year), ("track number", fields.trackNumber), ("track total", fields.trackTotal),
                ("disc number", fields.discNumber), ("disc total", fields.discTotal),
            ] {
                if let value, !(1 ... 9999).contains(value) {
                    throw AudioMetadataEditorError.invalidField(name)
                }
            }
            return fields
        }

        private static func runHelper(
            _ helper: URL,
            input: URL,
            output: URL,
            original: AudioMetadataFields,
            requested: AudioMetadataFields,
            artwork: URL?,
            removesArtwork: Bool
        ) async throws {
            var arguments = ["-i", input.path]
            if let artwork {
                arguments += ["-i", artwork.path, "-map", "0:a", "-map", "1:0"]
            } else {
                arguments += ["-map", "0:a"] + (removesArtwork ? [] : ["-map", "0:v?"])
            }
            arguments += ["-map_metadata", "0", "-map_chapters", "0", "-c", "copy"]
            if artwork != nil {
                // MP3 stores this as an ID3 front-cover picture; M4A as covr.
                arguments += ["-disposition:v:0", "attached_pic", "-metadata:s:v:0", "comment=Cover (front)"]
            }
            let values: [(String, String?, String?)] = [
                ("title", original.title, requested.title),
                ("artist", original.artist, requested.artist),
                ("album", original.album, requested.album),
                ("album_artist", original.albumArtist, requested.albumArtist),
                ("genre", original.genre, requested.genre),
                ("date", original.year.map(String.init), requested.year.map(String.init)),
                ("track", indexTag(number: original.trackNumber, total: original.trackTotal),
                 indexTag(number: requested.trackNumber, total: requested.trackTotal)),
                ("disc", indexTag(number: original.discNumber, total: original.discTotal),
                 indexTag(number: requested.discNumber, total: requested.discTotal)),
            ]
            // Only changed fields are passed, so tags the sheet does not
            // model (a full release date, say) survive untouched.
            for (key, oldValue, newValue) in values where oldValue != newValue {
                arguments += ["-metadata", "\(key)=\(newValue ?? "")"]
            }
            arguments += ["-f", input.pathExtension.lowercased() == "mp3" ? "mp3" : "mp4", output.path]

            let logURL = input.deletingLastPathComponent().appendingPathComponent("metadata-editor.log")
            do {
                try await FFmpegHelper.run(helper, arguments: arguments, logURL: logURL)
            } catch is FFmpegHelper.Failure {
                throw AudioMetadataEditorError.rewriteFailed
            }
        }

        private static func indexTag(number: Int?, total: Int?) -> String? {
            guard let number else { return nil }
            return total.map { "\(number)/\($0)" } ?? String(number)
        }

        private static func validate(
            _ output: URL,
            requested: AudioMetadataFields,
            expectedArtwork: Data?,
            originalAudio: AudioSignature
        ) async throws {
            guard let size = try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
                throw AudioMetadataEditorError.validationFailed
            }
            let outputAudio = try await audioSignature(at: output)
            guard outputAudio.streamCount == originalAudio.streamCount,
                  outputAudio.mediaSubtypes == originalAudio.mediaSubtypes,
                  outputAudio.sampleRates == originalAudio.sampleRates,
                  outputAudio.channelCounts == originalAudio.channelCounts,
                  abs(outputAudio.duration - originalAudio.duration) < 0.05
            else { throw AudioMetadataEditorError.validationFailed }

            let rewritten = try await MetadataReader.read(from: output)
            guard AudioMetadataFields(metadata: rewritten).normalized == requested,
                  rewritten.artwork == expectedArtwork
            else { throw AudioMetadataEditorError.validationFailed }
        }

        private static func audioSignature(at url: URL) async throws -> AudioSignature {
            let asset = AVURLAsset(url: url)
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard playable, duration.isNumeric, duration.seconds > 0, !tracks.isEmpty else {
                throw AudioMetadataEditorError.validationFailed
            }
            var subtypes: [UInt32] = []
            var sampleRates: [Double] = []
            var channelCounts: [UInt32] = []
            for track in tracks {
                let descriptions = try await track.load(.formatDescriptions)
                guard let description = descriptions.first else {
                    throw AudioMetadataEditorError.validationFailed
                }
                subtypes.append(CMFormatDescriptionGetMediaSubType(description))
                let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee
                sampleRates.append(basic?.mSampleRate ?? 0)
                channelCounts.append(basic?.mChannelsPerFrame ?? 0)
            }
            return AudioSignature(
                duration: duration.seconds,
                streamCount: tracks.count,
                mediaSubtypes: subtypes,
                sampleRates: sampleRates,
                channelCounts: channelCounts
            )
        }

        private static func replace(
            source: URL,
            with candidate: URL,
            relativePath: String,
            root: LibraryRoot,
            originalVersion: FileVersion
        ) throws {
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var operationError: Error?
            coordinator.coordinate(writingItemAt: source, options: .forReplacing, error: &coordinationError) { coordinatedURL in
                do {
                    let expected = try editableFileURL(relativePath, in: root, allowsAudiobook: true)
                    guard coordinatedURL.standardizedFileURL == expected,
                          try version(of: coordinatedURL) == originalVersion
                    else { throw AudioMetadataEditorError.fileChanged }
                    _ = try FileManager.default.replaceItemAt(
                        coordinatedURL,
                        withItemAt: candidate,
                        backupItemName: nil,
                        options: []
                    )
                } catch {
                    operationError = error
                }
            }
            if let operationError { throw operationError }
            if coordinationError != nil { throw AudioMetadataEditorError.replacementFailed }
        }
    }
#endif
