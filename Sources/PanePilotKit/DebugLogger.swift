import Foundation

final class DebugLogger: @unchecked Sendable {
    static let shared = DebugLogger()

    let logFileURL: URL
    // File I/O stays off the main thread and serialized through one queue to keep logging
    // low-risk even when multiple parts of the app emit diagnostics at once.
    private let queue = DispatchQueue(label: "PanePilot.DebugLogger", qos: .utility)
    private var loggingEnabled: Bool

    private init() {
        loggingEnabled = AppPreferences.debugLoggingEnabled
        let fm = FileManager.default
        let baseDir = fm.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("PanePilot", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("PanePilotLogs", isDirectory: true)

        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        self.logFileURL = baseDir.appendingPathComponent("PanePilot.log")
        if !fm.fileExists(atPath: logFileURL.path) {
            fm.createFile(atPath: logFileURL.path, contents: nil)
        }
    }

    // MARK: - Public Logging API

    func info(_ message: String) {
        guard isEnabled() else { return }
        write(level: "INFO", message: message)
    }

    func warn(_ message: String) {
        guard isEnabled() else { return }
        write(level: "WARN", message: message)
    }

    func error(_ message: String) {
        guard isEnabled() else { return }
        write(level: "ERROR", message: message)
    }

    // MARK: - State

    func setEnabled(_ enabled: Bool) {
        loggingEnabled = enabled
        AppPreferences.debugLoggingEnabled = enabled
        if enabled {
            write(level: "INFO", message: "Debug logging enabled.")
        }
    }

    func isEnabled() -> Bool {
        loggingEnabled
    }

    // MARK: - File Output

    private func write(level: String, message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) [\(level)] \(message)\n"

        queue.async { [logFileURL] in
            guard let handle = try? FileHandle(forWritingTo: logFileURL) else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } catch {
                // Avoid recursive logging.
            }
        }
    }
}
