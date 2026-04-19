import Foundation

/// A file-backed diagnostic logger for in-process events.
///
/// All log entries are written to `~/Library/Logs/PanePilot/PanePilot.log` with an ISO 8601
/// timestamp and a severity level tag. Writes are serialised on a dedicated background queue so
/// logging never blocks the main thread and is safe to call from any isolation context.
///
/// Logging can be toggled at runtime via `setEnabled(_:)`. The preference is persisted through
/// `AppPreferences` so the choice survives restarts. Logging is **on** by default for new
/// installs to ensure setup and permission problems leave a trace without requiring the user to
/// opt in first.
///
/// `DebugLogger` is declared `@unchecked Sendable` because `loggingEnabled` is mutated only on
/// the main thread via `setEnabled(_:)` and read from any context under an accept-race-for-bool
/// policy (a stale read here is harmless).
final class DebugLogger: @unchecked Sendable {
    static let shared = DebugLogger()

    /// The URL of the active log file. Exposed so Settings can show an "Open log" button.
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

    /// Writes an informational message to the log.
    func info(_ message: String) {
        guard isEnabled() else { return }
        write(level: "INFO", message: message)
    }

    /// Writes a warning message to the log.
    func warn(_ message: String) {
        guard isEnabled() else { return }
        write(level: "WARN", message: message)
    }

    /// Writes an error message to the log.
    func error(_ message: String) {
        guard isEnabled() else { return }
        write(level: "ERROR", message: message)
    }

    // MARK: - State

    /// Enables or disables logging and persists the preference.
    ///
    /// When enabling, a confirmation entry is written so the log always starts with a known
    /// timestamp even if prior entries were suppressed.
    func setEnabled(_ enabled: Bool) {
        loggingEnabled = enabled
        AppPreferences.debugLoggingEnabled = enabled
        if enabled {
            write(level: "INFO", message: "Debug logging enabled.")
        }
    }

    /// Returns `true` if logging is currently active.
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
