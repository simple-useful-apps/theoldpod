#if os(macOS)
    import AVFoundation
    import Foundation

    struct WMAConversion {
        let outputURL: URL
        let temporaryDirectory: URL
        let warnings: [String]

        func removeTemporaryFiles() {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    enum WMAConversionError: Error {
        case helperMissing
        case stagingFailed
        case conversionFailed(String)
        case invalidOutput
    }

    struct WMAConverter {
        private let fileManager = FileManager.default

        func convert(_ source: URL) async throws -> WMAConversion {
            guard let helperURL = Self.helperURL else { throw WMAConversionError.helperMissing }

            let temporaryDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("TheOldPod-WMA-\(UUID().uuidString)", isDirectory: true)
            do {
                try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
                let stagedInput = temporaryDirectory.appendingPathComponent("input.wma")
                try fileManager.copyItem(at: source, to: stagedInput)
                let output = temporaryDirectory.appendingPathComponent("output.m4a")
                do {
                    try await run(helperURL, input: stagedInput, output: output, includeArtwork: true)
                    try Task.checkCancellation()
                    try await validate(output)
                    try Task.checkCancellation()
                    return WMAConversion(outputURL: output, temporaryDirectory: temporaryDirectory, warnings: [])
                } catch let firstError {
                    if firstError is CancellationError { throw firstError }
                    try? fileManager.removeItem(at: output)
                    do {
                        try await run(helperURL, input: stagedInput, output: output, includeArtwork: false)
                        try Task.checkCancellation()
                        try await validate(output)
                        try Task.checkCancellation()
                        return WMAConversion(
                            outputURL: output,
                            temporaryDirectory: temporaryDirectory,
                            warnings: ["Audio was imported, but embedded artwork could not be preserved."]
                        )
                    } catch {
                        if error is CancellationError || Task.isCancelled { throw CancellationError() }
                        throw firstError
                    }
                }
            } catch {
                try? fileManager.removeItem(at: temporaryDirectory)
                if error is CancellationError { throw error }
                if error is WMAConversionError { throw error }
                throw WMAConversionError.stagingFailed
            }
        }

        static func userMessage(for error: Error) -> String {
            switch error {
            case WMAConversionError.helperMissing:
                "The built-in WMA converter is unavailable. Reinstall The Old Pod."
            case WMAConversionError.stagingFailed:
                "The file could not be prepared for conversion."
            case let WMAConversionError.conversionFailed(detail):
                detail.isEmpty ? "The WMA file could not be converted. It may be damaged or DRM-protected." : detail
            case WMAConversionError.invalidOutput:
                "Conversion did not produce a valid audio file."
            default:
                "The WMA file could not be converted."
            }
        }

        private static var helperURL: URL? {
            #if DEBUG
                if let override = ProcessInfo.processInfo.environment["OLDPOD_WMA_HELPER"], !override.isEmpty {
                    return URL(fileURLWithPath: override)
                }
            #endif
            guard let executable = Bundle.main.executableURL else { return nil }
            let helper = executable.deletingLastPathComponent()
                .appendingPathComponent("../Helpers/TheOldPodWMAConverter").standardizedFileURL
            return FileManager.default.isExecutableFile(atPath: helper.path) ? helper : nil
        }

        private func run(_ helper: URL, input: URL, output: URL, includeArtwork: Bool) async throws {
            try Task.checkCancellation()
            let logURL = input.deletingLastPathComponent().appendingPathComponent("converter.log")
            fileManager.createFile(atPath: logURL.path, contents: nil)
            let log = try FileHandle(forWritingTo: logURL)
            defer { try? log.close() }

            let process = Process()
            process.executableURL = helper
            process.arguments = [
                "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                "-i", input.path,
                "-map", "0:a:0",
            ] + (includeArtwork ? ["-map", "0:v?", "-c:v", "copy"] : ["-vn"]) + [
                "-map_metadata", "0",
                "-c:a", "aac", "-b:a", "192k",
                "-movflags", "+faststart",
                "-f", "mp4",
                output.path,
            ]
            process.standardOutput = log
            process.standardError = log

            let box = ProcessBox(process)
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { _ in continuation.resume() }
                    do {
                        try process.run()
                        if Task.isCancelled { process.terminate() }
                    } catch {
                        process.terminationHandler = nil
                        continuation.resume(throwing: error)
                    }
                }
                try Task.checkCancellation()
                guard process.terminationStatus == 0 else {
                    let detail = (try? String(contentsOf: logURL, encoding: .utf8))?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    throw WMAConversionError.conversionFailed(Self.friendlyFailure(detail))
                }
            } onCancel: {
                box.terminate()
            }
        }

        private func validate(_ output: URL) async throws {
            guard let size = try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
                throw WMAConversionError.invalidOutput
            }
            let asset = AVURLAsset(url: output)
            do {
                let playable = try await asset.load(.isPlayable)
                let duration = try await asset.load(.duration)
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                guard playable, duration.isNumeric, duration.seconds > 0, !tracks.isEmpty else {
                    throw WMAConversionError.invalidOutput
                }
            } catch {
                throw WMAConversionError.invalidOutput
            }
        }

        private static func friendlyFailure(_ detail: String) -> String {
            let lowered = detail.lowercased()
            if lowered.contains("drm") || lowered.contains("encrypted") || lowered.contains("digital rights") {
                return "This WMA file appears to be DRM-protected and cannot be imported."
            }
            return "The WMA file could not be converted. It may be damaged or DRM-protected."
        }
    }

    private final class ProcessBox: @unchecked Sendable {
        private let process: Process

        init(_ process: Process) {
            self.process = process
        }

        func terminate() {
            if process.isRunning { process.terminate() }
        }
    }
#endif
