import Foundation
import OSLog
import UIKit

public enum PrismLogSeverity: String, Codable, Sendable, CaseIterable, Identifiable {
    case debug
    case info
    case warning
    case error
    case fault

    public var id: String { rawValue }

    public var badgeLabel: String {
        rawValue.uppercased()
    }

    public var isWarningOrError: Bool {
        self == .warning || self == .error || self == .fault
    }

    public var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .fault: return .fault
        }
    }
}

public enum PrismLogCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case app = "App"
    case browser = "Browser"
    case downloader = "Downloader"
    case player = "Player"
    case adBlock = "AdBlock"
    case media = "Media"
    case vault = "Vault"

    public var id: String { rawValue }
}

public struct PrismLogEntry: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let timestampISO8601: String
    public let severity: PrismLogSeverity
    public let category: PrismLogCategory
    public let file: String
    public let line: Int
    public let message: String

    public init(
        id: UUID = UUID(),
        timestampISO8601: String,
        severity: PrismLogSeverity,
        category: PrismLogCategory,
        file: String,
        line: Int,
        message: String
    ) {
        self.id = id
        self.timestampISO8601 = timestampISO8601
        self.severity = severity
        self.category = category
        self.file = file
        self.line = line
        self.message = message
    }

    public var formattedLine: String {
        "[\(timestampISO8601)] [\(severity.badgeLabel)] [\(category.rawValue)] (\(file):\(line)) \(message)"
    }
}

/// Thread-safe persistent rolling logger mirroring structured events to OSLog and `ApplicationSupport/Diagnostics/prism_logs.jsonl`.
/// Strictly capped at 2 MB / 3,000 entries, zero main-thread blocking, zero idle timers, and automatic privacy redaction.
public actor PrismLogCenter {
    public static let shared = PrismLogCenter()

    private static let maxFileBytes = 2 * 1024 * 1024
    private static let maxStoredEntries = 3_000
    private static let subsystem = "com.prismdm.ios"

    private var entries: [PrismLogEntry] = []
    private var hasLoadedDisk = false
    private let logFileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(customLogDirectory: URL? = nil) {
        let dir: URL
        if let customLogDirectory {
            dir = customLogDirectory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            dir = support.appendingPathComponent("Diagnostics", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var excludedDir = dir
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        try? excludedDir.setResourceValues(rv)
        self.logFileURL = dir.appendingPathComponent("prism_logs.jsonl")
    }

    /// Fire-and-forget convenience entry point safe to call from any actor or thread.
    public nonisolated static func record(
        _ severity: PrismLogSeverity,
        category: PrismLogCategory,
        _ message: String,
        isPrivateContext: Bool = false,
        file: String = #fileID,
        line: Int = #line
    ) {
        let sanitized = redact(message, isPrivateContext: isPrivateContext)
        let shortFile = (file as NSString).lastPathComponent
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        logger.log(level: severity.osLogType, "\(shortFile, privacy: .public):\(line, privacy: .public) \(sanitized, privacy: .public)")

        Task.detached(priority: .utility) {
            await PrismLogCenter.shared.append(
                severity: severity,
                category: category,
                message: sanitized,
                file: shortFile,
                line: line
            )
        }
    }

    public func append(
        severity: PrismLogSeverity,
        category: PrismLogCategory,
        message: String,
        file: String,
        line: Int
    ) {
        loadFromDiskIfNeeded()
        let entry = PrismLogEntry(
            timestampISO8601: ISO8601DateFormatter().string(from: Date()),
            severity: severity,
            category: category,
            file: file,
            line: line,
            message: message
        )
        entries.append(entry)
        if entries.count > Self.maxStoredEntries {
            entries.removeFirst(entries.count - Self.maxStoredEntries)
            rewriteDiskFile()
        } else {
            appendLineToDisk(entry)
        }
    }

    public func allEntries() -> [PrismLogEntry] {
        loadFromDiskIfNeeded()
        return entries.reversed()
    }

    public func warningAndErrorEntries() -> [PrismLogEntry] {
        loadFromDiskIfNeeded()
        return entries.filter { $0.severity.isWarningOrError }.reversed()
    }

    public func recentBreadcrumbs(limit: Int = 40) -> [PrismLogEntry] {
        loadFromDiskIfNeeded()
        return Array(entries.suffix(max(1, limit)))
    }

    public func warningAndErrorCount() -> Int {
        loadFromDiskIfNeeded()
        return entries.reduce(0) { $0 + ($1.severity.isWarningOrError ? 1 : 0) }
    }

    public func clearAll() {
        entries.removeAll()
        hasLoadedDisk = true
        try? FileManager.default.removeItem(at: logFileURL)
    }

    public func clearWarningsAndErrors() {
        loadFromDiskIfNeeded()
        entries.removeAll { $0.severity.isWarningOrError }
        rewriteDiskFile()
    }

    /// Strict privacy redaction before any log leaves memory or hits disk.
    public nonisolated static func redact(_ raw: String, isPrivateContext: Bool = false) -> String {
        var text = raw
        if isPrivateContext {
            text = text.replacingOccurrences(
                of: #"https?://[^\s"'<>]+"#,
                with: "<redacted-private-url>",
                options: .regularExpression
            )
        }
        // Redact Cookie, Authorization, Bearer tokens, and PINs
        let patterns: [(String, String)] = [
            (#"(?i)(cookie\s*[:=]\s*)[^\r\n]+"#, "$1<redacted>"),
            (#"(?i)(authorization\s*[:=]\s*)[^\r\n]+"#, "$1<redacted>"),
            (#"(?i)(bearer\s+)[A-Za-z0-9\-._~+/]+=*"#, "$1<redacted>"),
            (#"(?i)(pin\s*[:=]\s*)\d{4,}"#, "$1<redacted>"),
            (#"PrivateVault/[^\s"'<>]+"#, "PrivateVault/<redacted>"),
        ]
        for (pattern, replacement) in patterns {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return text
    }

    public nonisolated static func buildEnvironmentHeader(
        activeDownloader: String,
        activeTheme: String
    ) -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let model = deviceHardwareIdentifier()
        let freeDisk = formattedFreeDiskSpace()
        return "PrismDM v\(version) (\(build)) | \(model) | iOS \(osVersion) | Downloader: \(activeDownloader) | Theme: \(activeTheme) | Free Disk: \(freeDisk)"
    }

    public nonisolated static func formatForAntigravity(
        entries: [PrismLogEntry],
        activeDownloader: String,
        activeTheme: String
    ) -> String {
        let header = buildEnvironmentHeader(activeDownloader: activeDownloader, activeTheme: activeTheme)
        let divider = String(repeating: "-", count: 64)
        let body = entries.isEmpty
            ? "(No log entries recorded)"
            : entries.map(\.formattedLine).joined(separator: "\n")
        return "\(header)\n\(divider)\n\(body)\n"
    }

    // MARK: - Disk Persistence

    private func loadFromDiskIfNeeded() {
        guard !hasLoadedDisk else { return }
        hasLoadedDisk = true
        guard let data = try? Data(contentsOf: logFileURL),
              let content = String(data: data, encoding: .utf8) else {
            return
        }
        var loaded: [PrismLogEntry] = []
        for line in content.split(whereSeparator: \.isNewline) {
            if let lineData = String(line).data(using: .utf8),
               let entry = try? decoder.decode(PrismLogEntry.self, from: lineData) {
                loaded.append(entry)
            }
        }
        if loaded.count > Self.maxStoredEntries {
            loaded.removeFirst(loaded.count - Self.maxStoredEntries)
        }
        entries = loaded
    }

    private func appendLineToDisk(_ entry: PrismLogEntry) {
        guard var lineData = try? encoder.encode(entry) else { return }
        lineData.append(0x0A)
        let fm = FileManager.default
        if !fm.fileExists(atPath: logFileURL.path) {
            try? lineData.write(to: logFileURL, options: .atomic)
            return
        }
        if let attrs = try? fm.attributesOfItem(atPath: logFileURL.path),
           let size = (attrs[.size] as? NSNumber)?.intValue,
           size + lineData.count > Self.maxFileBytes {
            let keepCount = max(1, entries.count / 2)
            entries = Array(entries.suffix(keepCount))
            rewriteDiskFile()
            return
        }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: lineData)
        }
    }

    private func rewriteDiskFile() {
        var buffer = Data()
        buffer.reserveCapacity(entries.count * 160)
        for entry in entries {
            if let encoded = try? encoder.encode(entry) {
                buffer.append(encoded)
                buffer.append(0x0A)
            }
        }
        try? buffer.write(to: logFileURL, options: .atomic)
    }

    private nonisolated static func deviceHardwareIdentifier() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    private nonisolated static func formattedFreeDiskSpace() -> String {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let values = try? docs.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]) else {
            return "Unknown"
        }
        let bytes = values.volumeAvailableCapacityForImportantUsage
            ?? values.volumeAvailableCapacity.map(Int64.init)
            ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
