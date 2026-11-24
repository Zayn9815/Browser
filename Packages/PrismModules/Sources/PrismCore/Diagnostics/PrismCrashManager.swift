import Foundation
import KSCrashFilters
import KSCrashRecording
import Observation

public struct PrismCrashReportSummary: Identifiable, Sendable, Equatable {
    public let id: Int64
    public let date: Date
    public let exceptionOrSignal: String
    public let crashedThread: String
    public let reason: String

    public init(
        id: Int64,
        date: Date,
        exceptionOrSignal: String,
        crashedThread: String,
        reason: String
    ) {
        self.id = id
        self.date = date
        self.exceptionOrSignal = exceptionOrSignal
        self.crashedThread = crashedThread
        self.reason = reason
    }
}

/// Local-only offline crash capture manager backed by `kstenerud/KSCrash` (MIT).
/// Zero telemetry or remote uploads; stores up to 20 crash reports on disk for on-device inspection.
@Observable
@MainActor
public final class PrismCrashManager {
    public static let shared = PrismCrashManager()

    public private(set) var isInstalled = false
    public private(set) var crashSummaries: [PrismCrashReportSummary] = []
    public private(set) var crashedLastLaunch = false

    public var crashCount: Int {
        crashSummaries.count
    }

    public init() {}

    public func install() {
        guard !isInstalled else { return }

        let config = KSCrashConfiguration()
        config.monitors = [
            .machException,
            .signal,
            .cppException,
            .nsException,
            .watchdog,
            .termination,
            .userReported,
        ]
        config.enableCompactBinaryImages = true
        config.reportStoreConfiguration.maxReportCount = 20
        config.reportStoreConfiguration.reportCleanupPolicy = .never

        do {
            try KSCrash.shared.install(with: config)
            isInstalled = true
            crashedLastLaunch = KSCrash.shared.crashedLastLaunch
            if crashedLastLaunch {
                PrismLogCenter.record(
                    .fault,
                    category: .app,
                    "Previous session terminated unexpectedly; crash report captured by KSCrash."
                )
            }
            refreshSummaries()
        } catch {
            PrismLogCenter.record(.error, category: .app, "KSCrash install failed: \(error.localizedDescription)")
        }
    }

    public func refreshSummaries() {
        guard let store = KSCrash.shared.reportStore else {
            crashSummaries = []
            return
        }
        let ids = store.reportIDs.map(\.int64Value).sorted(by: >)
        var summaries: [PrismCrashReportSummary] = []
        summaries.reserveCapacity(ids.count)

        let isoFormatter = ISO8601DateFormatter()
        for reportID in ids {
            guard let report = store.report(for: reportID) else { continue }
            let dict = report.value
            let reportMeta = dict["report"] as? [String: Any]
            let crashDict = dict["crash"] as? [String: Any]
            let errorDict = crashDict?["error"] as? [String: Any]

            let date: Date = {
                if let ts = reportMeta?["timestamp"] as? String, let parsed = isoFormatter.date(from: ts) {
                    return parsed
                }
                if let epoch = reportMeta?["timestamp"] as? Double {
                    return Date(timeIntervalSince1970: epoch)
                }
                return .now
            }()

            let signalName = (errorDict?["signal"] as? [String: Any])?["name"] as? String
            let machName = (errorDict?["mach"] as? [String: Any])?["exception_name"] as? String
            let nsExcName = (errorDict?["nsexception"] as? [String: Any])?["name"] as? String
            let cppName = (errorDict?["cpp_exception"] as? [String: Any])?["name"] as? String
            let typeName = errorDict?["type"] as? String ?? "Crash"

            let label = [nsExcName, cppName, signalName, machName]
                .compactMap { $0 }
                .first { !$0.isEmpty } ?? typeName

            let reason = (errorDict?["reason"] as? String)
                ?? (crashDict?["diagnosis"] as? String)
                ?? "Unexpected termination"

            var threadName = "Main / Unknown Thread"
            if let threads = crashDict?["threads"] as? [[String: Any]],
               let crashed = threads.first(where: { ($0["crashed"] as? Bool) == true }) {
                let idx = crashed["index"] as? Int ?? 0
                let name = (crashed["name"] as? String) ?? (crashed["dispatch_queue"] as? String) ?? ""
                threadName = name.isEmpty ? "Thread \(idx)" : "Thread \(idx) (\(name))"
            }

            summaries.append(
                PrismCrashReportSummary(
                    id: reportID,
                    date: date,
                    exceptionOrSignal: label,
                    crashedThread: threadName,
                    reason: reason
                )
            )
        }
        crashSummaries = summaries
    }

    public func loadFormattedAppleReport(
        reportID: Int64,
        activeDownloader: String,
        activeTheme: String
    ) async -> String {
        let envHeader = PrismLogCenter.buildEnvironmentHeader(
            activeDownloader: activeDownloader,
            activeTheme: activeTheme
        )
        guard let store = KSCrash.shared.reportStore,
              let dictReport = store.report(for: reportID) else {
            return "\(envHeader)\n\nCrash report #\(reportID) could not be read from disk."
        }

        let appleText: String = await withCheckedContinuation { continuation in
            let filter = CrashReportFilterAppleFmt(reportStyle: .symbolicatedSideBySide)
            filter.filterReports([dictReport]) { filtered, _ in
                if let strReport = filtered?.first as? CrashReportString, !strReport.value.isEmpty {
                    continuation.resume(returning: strReport.value)
                    return
                }
                if let jsonData = try? JSONSerialization.data(
                    withJSONObject: dictReport.value,
                    options: [.prettyPrinted, .sortedKeys]
                ), let fallback = String(data: jsonData, encoding: .utf8) {
                    continuation.resume(returning: fallback)
                    return
                }
                continuation.resume(returning: "Unable to format crash report #\(reportID).")
            }
        }

        let breadcrumbs = await PrismLogCenter.shared.recentBreadcrumbs(limit: 40)
        let breadcrumbText = breadcrumbs.isEmpty
            ? "(No recent breadcrumbs)"
            : breadcrumbs.map(\.formattedLine).joined(separator: "\n")

        return """
        \(envHeader)
        ================================================================
        \(appleText)

        --- Recent PrismDM Breadcrumbs ---
        \(breadcrumbText)
        """
    }

    public func deleteReport(id: Int64) {
        KSCrash.shared.reportStore?.deleteReport(with: id)
        refreshSummaries()
    }

    public func deleteAllReports() {
        KSCrash.shared.reportStore?.deleteAllReports()
        refreshSummaries()
    }

    public static var diagnosticsVersionSummary: String {
        "KSCrash 2.6 (Offline Local Store)"
    }
}
