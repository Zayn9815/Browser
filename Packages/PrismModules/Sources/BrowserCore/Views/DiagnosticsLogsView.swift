import ParallelDownloader
import PrismCore
import SwiftUI
import UIKit

public struct DiagnosticsLogsView: View {
    @Bindable private var downloadStore: ParallelDownloadStore
    @State private var crashManager = PrismCrashManager.shared
    @State private var themeEngine = PrismThemeEngine.shared

    @State private var selectedSegment = 0
    @State private var selectedCategory: PrismLogCategory? = nil
    @State private var searchText = ""
    @State private var allEntries: [PrismLogEntry] = []
    @State private var copiedConfirmation = false
    @State private var exportedShareURL: URL?
    @State private var selectedCrashReport: PrismCrashReportSummary?
    @State private var loadedCrashReportText: String = ""
    @State private var isLoadingCrashText = false

    public init(downloadStore: ParallelDownloadStore) {
        self.downloadStore = downloadStore
    }

    private var filteredLogs: [PrismLogEntry] {
        var result = allEntries
        if selectedSegment == 1 {
            result = result.filter { $0.severity.isWarningOrError }
        }
        if let selectedCategory {
            result = result.filter { $0.category == selectedCategory }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            result = result.filter {
                $0.message.localizedCaseInsensitiveContains(q) ||
                $0.category.rawValue.localizedCaseInsensitiveContains(q) ||
                $0.file.localizedCaseInsensitiveContains(q)
            }
        }
        return result.reversed()
    }

    private var warningErrorCount: Int {
        allEntries.filter { $0.severity.isWarningOrError }.count
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        VStack(spacing: 0) {
            Picker("Diagnostics Section", selection: $selectedSegment) {
                Text("All Logs (\(allEntries.count))").tag(0)
                Text("Errors (\(warningErrorCount))").tag(1)
                Text("Crashes (\(crashManager.crashCount))").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if selectedSegment < 2 {
                categoryFilterBar(tokens: tokens)
                logsListView(tokens: tokens)
            } else {
                crashReportsListView(tokens: tokens)
            }
        }
        .navigationTitle("Diagnostics & Logs")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Filter logs by message or module")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if selectedSegment < 2 {
                    Button {
                        Task { await copyLogsForAntigravity() }
                    } label: {
                        Image(systemName: copiedConfirmation ? "checkmark.circle.fill" : "doc.on.doc")
                    }
                    .accessibilityLabel("Copy Logs for Antigravity")

                    if let exportedShareURL {
                        ShareLink(item: exportedShareURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }

                    Button(role: .destructive) {
                        Task {
                            await PrismLogCenter.shared.clearAll()
                            await refreshDiagnostics()
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Clear Logs")
                } else if !crashManager.crashSummaries.isEmpty {
                    Button(role: .destructive) {
                        crashManager.deleteAllReports()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Clear All Crash Reports")
                }
            }
        }
        .task {
            await refreshDiagnostics()
        }
        .sheet(item: $selectedCrashReport) { summary in
            NavigationStack {
                Group {
                    if isLoadingCrashText {
                        ProgressView("Formatting Apple crash report…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView([.vertical, .horizontal]) {
                            Text(loadedCrashReportText)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(14)
                        }
                    }
                }
                .navigationTitle(summary.exceptionOrSignal)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { selectedCrashReport = nil }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            UIPasteboard.general.string = loadedCrashReportText
                            flashCopiedConfirmation()
                        } label: {
                            Label("Copy", systemImage: copiedConfirmation ? "checkmark" : "doc.on.doc")
                        }
                        .disabled(loadedCrashReportText.isEmpty)

                        if let crashURL = writeTempExportFile(text: loadedCrashReportText, filename: "PrismDM_Crash_\(summary.id).crash") {
                            ShareLink(item: crashURL) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
        }
        .tint(tokens.accent)
    }

    private func categoryFilterBar(tokens: PrismThemeTokens) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", isSelected: selectedCategory == nil, tokens: tokens) {
                    selectedCategory = nil
                }
                ForEach(PrismLogCategory.allCases) { cat in
                    filterChip(title: cat.rawValue, isSelected: selectedCategory == cat, tokens: tokens) {
                        selectedCategory = (selectedCategory == cat) ? nil : cat
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func filterChip(
        title: String,
        isSelected: Bool,
        tokens: PrismThemeTokens,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? tokens.accentText : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected ? tokens.accent : Color.secondary.opacity(0.16),
                    in: Capsule()
                )
        }
        .buttonStyle(.borderless)
    }

    private func logsListView(tokens: PrismThemeTokens) -> some View {
        List {
            Section {
                Button {
                    Task { await copyLogsForAntigravity() }
                } label: {
                    HStack {
                        Label(
                            copiedConfirmation ? "Copied to Clipboard!" : "Copy Logs for Antigravity",
                            systemImage: copiedConfirmation ? "checkmark.circle.fill" : "doc.on.clipboard.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tokens.accent)
                        Spacer()
                        Text("1-Tap Paste")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if filteredLogs.isEmpty {
                ContentUnavailableView(
                    selectedSegment == 1 ? "No Warnings or Errors" : "No Logs Recorded Yet",
                    systemImage: selectedSegment == 1 ? "checkmark.shield.fill" : "doc.text.magnifyingglass",
                    description: Text("All logs stay strictly local on your iPhone with tokens, cookies, and private URLs redacted.")
                )
            } else {
                Section("\(filteredLogs.count) Entry(s)") {
                    ForEach(filteredLogs) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(entry.severity.badgeLabel)
                                    .font(.caption2.weight(.bold).monospaced())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(severityColor(entry.severity), in: Capsule())

                                Text(entry.category.rawValue)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text(shortTimestamp(entry.timestampISO8601))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)

                            Text("\(entry.file):\(entry.line)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await refreshDiagnostics()
        }
    }

    private func crashReportsListView(tokens: PrismThemeTokens) -> some View {
        List {
            if crashManager.crashSummaries.isEmpty {
                ContentUnavailableView(
                    "No Crash Reports",
                    systemImage: "checkmark.seal.fill",
                    description: Text("KSCrash runs 100% locally offline. Any unexpected termination is captured here for 1-tap Antigravity inspection.")
                )
            } else {
                Section("Captured Local Crash Reports") {
                    ForEach(crashManager.crashSummaries) { summary in
                        Button {
                            selectedCrashReport = summary
                            isLoadingCrashText = true
                            loadedCrashReportText = ""
                            Task {
                                let reportText = await crashManager.loadFormattedAppleReport(
                                    reportID: summary.id,
                                    activeDownloader: downloadStore.defaultDownloaderMode.displayName,
                                    activeTheme: themeEngine.selectedTheme.displayName
                                )
                                loadedCrashReportText = reportText
                                isLoadingCrashText = false
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(summary.exceptionOrSignal)
                                        .font(.subheadline.weight(.bold).monospaced())
                                        .foregroundStyle(.red)
                                    Spacer()
                                    Text(summary.date, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(summary.crashedThread)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(summary.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                crashManager.deleteReport(id: summary.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            crashManager.refreshSummaries()
        }
    }

    private func refreshDiagnostics() async {
        crashManager.refreshSummaries()
        allEntries = await PrismLogCenter.shared.allEntries()
        let exportText = PrismLogCenter.formatForAntigravity(
            entries: filteredLogs,
            activeDownloader: downloadStore.defaultDownloaderMode.displayName,
            activeTheme: themeEngine.selectedTheme.displayName
        )
        exportedShareURL = writeTempExportFile(text: exportText, filename: "PrismDM_Diagnostics.log")
    }

    private func copyLogsForAntigravity() async {
        let text = PrismLogCenter.formatForAntigravity(
            entries: filteredLogs,
            activeDownloader: downloadStore.defaultDownloaderMode.displayName,
            activeTheme: themeEngine.selectedTheme.displayName
        )
        UIPasteboard.general.string = text
        flashCopiedConfirmation()
    }

    private func flashCopiedConfirmation() {
        copiedConfirmation = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.0))
            copiedConfirmation = false
        }
    }

    private func writeTempExportFile(text: String, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        guard let data = text.data(using: .utf8) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func severityColor(_ severity: PrismLogSeverity) -> Color {
        switch severity {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .fault: return .purple
        }
    }

    private func shortTimestamp(_ iso: String) -> String {
        if let tIdx = iso.firstIndex(of: "T") {
            let afterT = iso[iso.index(after: tIdx)...]
            return String(afterT.prefix(8))
        }
        return iso
    }
}
