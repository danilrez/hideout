#if HIDEOUT_DIAGNOSTICS
import AppKit
import Darwin
import Foundation
import OSLog

@MainActor
enum HideoutDiagnostics {
    private struct Entry: Encodable {
        let timestamp: String
        let sessionID: String
        let processID: Int32
        let event: String
        let fields: [String: String]
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.danilrez.hideout",
        category: "MenuBarDiagnostics"
    )
    private static let sessionID = UUID().uuidString
    private static let maximumFileSize = 2 * 1024 * 1024
    private static let archiveCount = 3
    private static var hasLoggedConfigurationCheck = false

    private static var applicationSupportHideoutDirectoryURL: URL? {
        guard let userHomeDirectory = currentUserHomeDirectory() else {
            return nil
        }

        return userHomeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Hideout", isDirectory: true)
    }

    private static var configurationFileURL: URL? {
        applicationSupportHideoutDirectoryURL?
            .appendingPathComponent("config.json", isDirectory: false)
    }

    private static func currentUserHomeDirectory() -> URL? {
        let suggestedBufferSize = sysconf(_SC_GETPW_R_SIZE_MAX)
        let bufferSize = suggestedBufferSize > 0 ? Int(suggestedBufferSize) : 16_384
        var record = passwd()
        var buffer = [CChar](repeating: 0, count: bufferSize)
        var result: UnsafeMutablePointer<passwd>?

        let status = buffer.withUnsafeMutableBufferPointer { bufferPointer in
            getpwuid_r(
                getuid(),
                &record,
                bufferPointer.baseAddress,
                bufferPointer.count,
                &result
            )
        }

        guard status == 0, result != nil, let homePath = record.pw_dir else {
            return nil
        }

        return URL(fileURLWithPath: String(cString: homePath), isDirectory: true)
    }

    static var isEnabled: Bool {
        configurationFileEnablesDiagnostics(at: configurationFileURL)
    }

    static func configurationFileEnablesDiagnostics(at url: URL?) -> Bool {
        guard let url else {
            logConfigurationCheck("userHomeUnavailable", at: nil)
            return false
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let nsError = error as NSError
            logConfigurationCheck("readFailed.\(nsError.domain).\(nsError.code)", at: url)
            return false
        }

        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            logConfigurationCheck("invalidJSON", at: url)
            return false
        }

        guard let object = json as? [String: Any] else {
            logConfigurationCheck("rootNotObject", at: url)
            return false
        }

        guard let debugValue = object["debug"] else {
            logConfigurationCheck("debugKeyMissing", at: url)
            return false
        }

        guard debugValue is String else {
            logConfigurationCheck("debugValueNotString", at: url)
            return false
        }

        logConfigurationCheck("enabled", at: url)
        return true
    }

    private static func logConfigurationCheck(_ result: String, at url: URL?) {
        guard !hasLoggedConfigurationCheck else { return }
        hasLoggedConfigurationCheck = true

        let location = url.map { $0.path.contains("/Containers/") ? "appContainer" : "userHome" }
            ?? "unresolved"
        logger.notice(
            "[HIDEOUT-DIAGNOSTICS] diagnostics.configurationCheck result=\(result, privacy: .public) location=\(location, privacy: .public)"
        )
    }

    private static var diagnosticsDirectoryURL: URL? {
        applicationSupportHideoutDirectoryURL?
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    static func record(_ event: String, fields: [String: String] = [:]) {
        guard isEnabled else { return }

        let entry = Entry(
            timestamp: Date().formatted(.iso8601),
            sessionID: sessionID,
            processID: ProcessInfo.processInfo.processIdentifier,
            event: event,
            fields: fields
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let line = (try? String(data: encoder.encode(entry), encoding: .utf8))
            ?? "{\"event\":\"diagnosticEncodingFailure\"}"

        logger.info("[HIDEOUT-DIAGNOSTICS] \(line, privacy: .public)")
        append(line)
    }

    static func openDiagnosticsFolder(source: String = "menuBar") {
        guard isEnabled else { return }
        record("diagnostics.folderOpenRequested", fields: ["source": source])

        guard let directoryURL = diagnosticsDirectoryURL else {
            logger.error("Unable to resolve the diagnostics directory")
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let opened = NSWorkspace.shared.open(directoryURL)
            record("diagnostics.folderOpened", fields: [
                "source": source,
                "success": String(opened)
            ])
        } catch {
            record("diagnostics.folderOpenFailed", fields: [
                "source": source,
                "error": String(describing: error)
            ])
        }
    }

    private static func append(_ line: String) {
        guard let directoryURL = diagnosticsDirectoryURL else { return }

        let fileManager = FileManager.default
        let logURL = directoryURL.appendingPathComponent("diagnostics.log", isDirectory: false)
        let data = Data((line + "\n").utf8)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: logURL.path) {
                fileManager.createFile(atPath: logURL.path, contents: nil)
            }
            try rotateLogsIfNeeded(
                at: logURL,
                directoryURL: directoryURL,
                incomingByteCount: data.count,
                fileManager: fileManager
            )

            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            logger.error("Unable to append diagnostics file: \(String(describing: error), privacy: .public)")
        }
    }

    private static func rotateLogsIfNeeded(
        at logURL: URL,
        directoryURL: URL,
        incomingByteCount: Int,
        fileManager: FileManager
    ) throws {
        let attributes = try fileManager.attributesOfItem(atPath: logURL.path)
        let currentSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard currentSize + incomingByteCount > maximumFileSize else { return }

        let oldestArchiveURL = archiveURL(generation: archiveCount, in: directoryURL)
        if fileManager.fileExists(atPath: oldestArchiveURL.path) {
            try fileManager.removeItem(at: oldestArchiveURL)
        }

        for generation in stride(from: archiveCount - 1, through: 1, by: -1) {
            let sourceURL = archiveURL(generation: generation, in: directoryURL)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }

            let destinationURL = archiveURL(generation: generation + 1, in: directoryURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }

        let firstArchiveURL = archiveURL(generation: 1, in: directoryURL)
        if fileManager.fileExists(atPath: firstArchiveURL.path) {
            try fileManager.removeItem(at: firstArchiveURL)
        }
        try fileManager.moveItem(at: logURL, to: firstArchiveURL)
        fileManager.createFile(atPath: logURL.path, contents: nil)
    }

    private static func archiveURL(generation: Int, in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent("diagnostics.\(generation).log", isDirectory: false)
    }
}
#else
import Foundation

@MainActor
enum HideoutDiagnostics {
    static func record(_ event: String, fields: [String: String] = [:]) {}

    static func openDiagnosticsFolder(source: String = "menuBar") {}
}
#endif
