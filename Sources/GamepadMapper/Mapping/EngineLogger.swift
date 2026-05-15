import Foundation

/// Minimal file-based logger for diagnosing background behavior in packaged builds.
/// Writes to ~/Library/Application Support/GamepadMapper/engine.log
enum EngineLogger {
    static let logURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = dir.appendingPathComponent("GamepadMapper")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("engine.log")
    }()

    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: .now)
        let line = "[\(timestamp)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: logURL)
        }
    }

    static func clear() {
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
    }
}
