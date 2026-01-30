import Foundation
import Combine

// Debug-only remote logger for Cursor debug mode.
// Sends small NDJSON-like payloads to the local ingest server.
enum DebugReporter {
    private static let endpoint = URL(string: "http://127.0.0.1:7244/ingest/3f651a28-61ab-4095-a6be-e7bdb9e750d4")!
    private static let sessionId = "debug-session"
    private static let runId = "run1"
    
    // #region agent log
    // If the local ingest server isn't reachable (common on real devices),
    // disable logging to avoid spamming URLSession and slowing the UI.
    private static let stateLock = NSLock()
    private static var isDisabled = false
    private static var onceKeys = Set<String>()
    private static let logFilePath = "/Users/strictly/Library/Mobile Documents/com~apple~CloudDocs/开发项目/iOS_Project/NoteLab/.cursor/debug.log"
    // #endregion

    static func log(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any] = [:]
    ) {
        #if DEBUG
        // #region agent log
        #if !targetEnvironment(simulator)
        // On real devices, 127.0.0.1 points to the device itself → connection refused.
        // Also, the macOS workspace path isn't writable on-device.
        // Keep logs silent rather than spamming network failures.
        return
        #endif
        
        stateLock.lock()
        let disabled = isDisabled
        stateLock.unlock()
        guard !disabled else { return }
        // #endregion
        
        var payload: [String: Any] = [
            "sessionId": sessionId,
            "runId": runId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]

        // Ensure JSON encodable
        if !JSONSerialization.isValidJSONObject(payload) {
            payload["data"] = ["note": "non-json data"]
        }

        // #region agent log
        // Prefer writing to the debug log file on simulator so we don't rely on the ingest server.
        if let lineData = try? JSONSerialization.data(withJSONObject: payload, options: []),
           var line = String(data: lineData, encoding: .utf8) {
            line.append("\n")
            if let bytes = line.data(using: .utf8) {
                do {
                    let url = URL(fileURLWithPath: logFilePath)
                    if FileManager.default.fileExists(atPath: logFilePath) {
                        let handle = try FileHandle(forWritingTo: url)
                        try handle.seekToEnd()
                        try handle.write(contentsOf: bytes)
                        try handle.close()
                    } else {
                        try bytes.write(to: url, options: [.atomic])
                    }
                } catch {
                    // Fall back to HTTP if file write fails for any reason.
                }
            }
        }
        // #endregion

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data()

        URLSession.shared.dataTask(with: req) { _, _, error in
            // #region agent log
            if error != nil {
                stateLock.lock()
                isDisabled = true
                stateLock.unlock()
            }
            // #endregion
        }.resume()
        #endif
    }

    // #region agent log
    /// Logs only once per `key` (thread-safe).
    static func logOnce(
        key: String,
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any] = [:]
    ) {
        #if DEBUG
        stateLock.lock()
        let isNew = onceKeys.insert(key).inserted
        stateLock.unlock()
        guard isNew else { return }
        // Call log after releasing the lock to avoid re-entrancy deadlock.
        log(hypothesisId: hypothesisId, location: location, message: message, data: data)
        #endif
    }
    // #endregion
}

