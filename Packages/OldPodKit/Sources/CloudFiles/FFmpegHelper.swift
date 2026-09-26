#if os(macOS)
    import Foundation

    /// The app's bundled minimal FFmpeg build, used for WMA conversion and
    /// tag rewriting.
    enum FFmpegHelper {
        struct Failure: Error {
            let log: String
        }

        static var url: URL? {
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

        /// Runs the helper to completion, collecting its output in `logURL`.
        /// Throws `Failure` carrying that output on a non-zero exit, and
        /// terminates the process if the calling task is cancelled.
        static func run(_ helper: URL, arguments: [String], logURL: URL) async throws {
            try Task.checkCancellation()
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let log = try FileHandle(forWritingTo: logURL)
            defer { try? log.close() }

            let process = Process()
            process.executableURL = helper
            process.arguments = ["-nostdin", "-hide_banner", "-loglevel", "error", "-y"] + arguments
            process.standardOutput = log
            process.standardError = log

            let box = ProcessBox(process)
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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
                    let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                    throw Failure(log: output.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } onCancel: {
                box.terminate()
            }
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
