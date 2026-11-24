import Foundation
import Observation
import SDMCore
import SwiftData
import VaultManager

private struct PersistedHLSTaskRecord: Codable, Sendable {
    let id: UUID
    let sourceURL: URL
    let resolvedFilename: String
    let destinationURL: URL?
    let state: DownloadState
    let downloadedBytes: UInt64
    let isIncognito: Bool
    let errorMessage: String?
    let createdAt: Date
}

@Observable
@MainActor
public final class ParallelDownloadStore: ParallelDownloadCoordinating {
    public private(set) var items: [UnifiedDownloadItem] = []
    public private(set) var engineStartupError: String?

    public var preferredHTTPBackend: DownloadEngineKind {
        didSet {
            UserDefaults.standard.set(preferredHTTPBackend.rawValue, forKey: Self.enginePrefKey)
            Task { [weak self] in
                try? await self?.sdmManager?.setDefaultEngine(self?.preferredHTTPBackend ?? .libcurl)
            }
        }
    }

    public var defaultConnectionsPerDownload: Int {
        didSet {
            let clamped = min(max(defaultConnectionsPerDownload, 1), 16)
            if clamped != defaultConnectionsPerDownload {
                defaultConnectionsPerDownload = clamped
            }
            UserDefaults.standard.set(clamped, forKey: Self.connectionsPrefKey)
        }
    }

    public var globalBandwidthLimitBytesPerSec: UInt64 {
        didSet {
            UserDefaults.standard.set(Int64(globalBandwidthLimitBytesPerSec), forKey: Self.bandwidthPrefKey)
        }
    }

    public var activeCount: Int {
        items.filter(\.isActive).count
    }

    public var aggregateBytesPerSecond: UInt64 {
        items.filter(\.isActive).reduce(0) { $0 &+ $1.speedBytesPerSecond }
    }

    public static let backgroundSessionIdentifier = "com.prismdm.ios.background-downloads"
    private static let enginePrefKey = "prismdm.v1.downloadEngine"
    private static let connectionsPrefKey = "prismdm.v1.downloadConnections"
    private static let bandwidthPrefKey = "prismdm.v1.downloadBandwidthCap"
    private static let hlsHistoryKey = "prismdm.v1.hlsTaskHistory"

    private let headerAdapter = BrowserSessionHeaderAdapter()
    private let hlsWorker = FFmpegHLSMuxerWorker()
    private let vaultService: VaultFileService
    private var modelContext: ModelContext?

    private var sdmManager: DownloadManager?
    private var sdmObservationTask: Task<Void, Never>?
    private var sdmSnapshotsByID: [UUID: UnifiedDownloadItem] = [:]
    private var hlsItemsByID: [UUID: UnifiedDownloadItem] = [:]
    private var hlsActiveTasks: [UUID: Task<Void, Never>] = [:]
    private var hlsRetryInputs: [UUID: (url: URL, title: String?, session: BrowserSessionContext?)] = [:]
    private var incognitoFlagsByTaskID: [UUID: Bool] = [:]
    private var registeredCompletedIDs: Set<UUID> = []

    /// 6 Hz (166 ms) UI publication throttling state (zero idle Timer loops)
    private var lastPublishTime: Date = .distantPast
    private var deferredFlushTask: Task<Void, Never>?

    public init(vaultService: VaultFileService = .shared) {
        self.vaultService = vaultService

        if let savedRaw = UserDefaults.standard.string(forKey: Self.enginePrefKey),
           let savedEngine = DownloadEngineKind(rawValue: savedRaw) {
            self.preferredHTTPBackend = savedEngine
        } else {
            self.preferredHTTPBackend = .libcurl
        }

        let savedConnections = UserDefaults.standard.integer(forKey: Self.connectionsPrefKey)
        self.defaultConnectionsPerDownload = (1...16).contains(savedConnections) ? savedConnections : 8

        let savedCap = UserDefaults.standard.object(forKey: Self.bandwidthPrefKey) as? Int64
        self.globalBandwidthLimitBytesPerSec = savedCap.map { UInt64(max(0, $0)) } ?? 0

        restorePersistedHLSHistory()
        startSDMCoreEngine()
    }

    public func attachModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    public func shutdown() async {
        sdmObservationTask?.cancel()
        sdmObservationTask = nil
        deferredFlushTask?.cancel()
        deferredFlushTask = nil
        for (id, task) in hlsActiveTasks {
            await hlsWorker.cancelTask(id)
            task.cancel()
        }
        hlsActiveTasks.removeAll()
        await sdmManager?.shutdown()
    }

    // MARK: - ParallelDownloadCoordinating

    @discardableResult
    public func enqueueHTTPDownload(
        url: URL,
        sessionContext: BrowserSessionContext?,
        preferredEngine: DownloadEngineKind? = nil,
        connectionLimit: Int? = nil,
        bandwidthLimitBytesPerSec: UInt64? = nil
    ) async throws -> UUID {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw DownloadAdapterError.invalidDownloadURL(url.absoluteString)
        }
        guard let sdmManager else {
            throw NSError(domain: "PrismDownloader", code: 1, userInfo: [
                NSLocalizedDescriptionKey: engineStartupError ?? "SDMCore engine is not initialized."
            ])
        }

        try headerAdapter.verifyDiskSpace(using: vaultService)

        let isIncognito = sessionContext?.isIncognito ?? false
        let destinationDir = try vaultService.vaultRootURL(isPrivate: isIncognito)
        let targetEngine = preferredEngine ?? preferredHTTPBackend

        let effectiveConnections: Int
        let effectiveBandwidth: UInt64?
        if targetEngine == .urlSession {
            effectiveConnections = 1
            effectiveBandwidth = nil
        } else {
            effectiveConnections = min(max(connectionLimit ?? defaultConnectionsPerDownload, 1), 16)
            let cap = bandwidthLimitBytesPerSec ?? (globalBandwidthLimitBytesPerSec > 0 ? globalBandwidthLimitBytesPerSec : nil)
            effectiveBandwidth = cap
        }

        let sdmContext = headerAdapter.makeSDMRequestContext(from: sessionContext, for: url)
        let downloadID = DownloadID()
        incognitoFlagsByTaskID[downloadID.rawValue] = isIncognito

        let request = DownloadRequest(
            id: downloadID,
            url: url,
            destinationDirectory: destinationDir,
            filename: sessionContext?.suggestedFilename,
            connectionLimit: effectiveConnections,
            bandwidthLimit: effectiveBandwidth,
            conflictPolicy: .rename,
            requestContext: sdmContext
        )

        _ = try await sdmManager.enqueue(request, using: targetEngine)
        return downloadID.rawValue
    }

    @discardableResult
    public func enqueueHLSStreamMux(
        manifestURL: URL,
        variantTitle: String?,
        sessionContext: BrowserSessionContext?
    ) async throws -> UUID {
        guard let scheme = manifestURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw DownloadAdapterError.invalidDownloadURL(manifestURL.absoluteString)
        }

        try headerAdapter.verifyDiskSpace(using: vaultService)

        let taskID = UUID()
        let isIncognito = sessionContext?.isIncognito ?? false
        incognitoFlagsByTaskID[taskID] = isIncognito
        hlsRetryInputs[taskID] = (manifestURL, variantTitle, sessionContext)

        let destinationDir = try vaultService.vaultRootURL(isPrivate: isIncognito)
        let rawName = (variantTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? variantTitle!
            : (sessionContext?.suggestedFilename ?? manifestURL.deletingPathExtension().lastPathComponent)
        let baseName = rawName.lowercased().hasSuffix(".mp4") ? rawName : "\(rawName).mp4"
        let outputURL = await vaultService.uniqueDestinationURL(in: destinationDir, preferredFilename: baseName)
        let crlfHeaders = headerAdapter.makeFFmpegCRLFHeaders(from: sessionContext, for: manifestURL)

        let initialItem = UnifiedDownloadItem(
            id: taskID,
            backend: .ffmpegHLSMuxer,
            sourceURL: manifestURL,
            resolvedFilename: outputURL.lastPathComponent,
            destinationURL: outputURL,
            state: .queued,
            totalBytes: nil,
            downloadedBytes: 0,
            speedBytesPerSecond: 0,
            etaSeconds: nil,
            mediaProgressFraction: 0,
            segments: [],
            errorMessage: nil,
            createdAt: .now
        )
        hlsItemsByID[taskID] = initialItem
        publishMergedItems(forceImmediate: true)
        persistHLSHistory()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = await self.hlsWorker.startRemux(
                taskID: taskID,
                sourceURL: manifestURL,
                outputURL: outputURL,
                crlfHeaders: crlfHeaders
            )
            for await event in stream {
                self.handleHLSMuxEvent(event, isIncognito: isIncognito)
            }
            self.hlsActiveTasks.removeValue(forKey: taskID)
        }
        hlsActiveTasks[taskID] = task
        return taskID
    }

    public func pause(_ id: UUID) async throws {
        if hlsItemsByID[id] != nil {
            await hlsWorker.cancelTask(id)
            hlsActiveTasks[id]?.cancel()
            hlsActiveTasks.removeValue(forKey: id)
            if let existing = hlsItemsByID[id] {
                hlsItemsByID[id] = UnifiedDownloadItem(
                    id: existing.id,
                    backend: .ffmpegHLSMuxer,
                    sourceURL: existing.sourceURL,
                    resolvedFilename: existing.resolvedFilename,
                    destinationURL: existing.destinationURL,
                    state: .paused,
                    totalBytes: existing.totalBytes,
                    downloadedBytes: existing.downloadedBytes,
                    speedBytesPerSecond: 0,
                    etaSeconds: nil,
                    mediaProgressFraction: existing.mediaProgressFraction,
                    segments: [],
                    errorMessage: nil,
                    createdAt: existing.createdAt
                )
                publishMergedItems(forceImmediate: true)
                persistHLSHistory()
            }
            return
        }
        try await sdmManager?.pause(DownloadID(rawValue: id))
    }

    public func resume(_ id: UUID) async throws {
        if hlsItemsByID[id] != nil {
            try await retry(id)
            return
        }
        try await sdmManager?.resume(DownloadID(rawValue: id))
    }

    public func cancel(_ id: UUID) async throws {
        if hlsItemsByID[id] != nil {
            await hlsWorker.cancelTask(id)
            hlsActiveTasks[id]?.cancel()
            hlsActiveTasks.removeValue(forKey: id)
            if let existing = hlsItemsByID[id] {
                if let dst = existing.destinationURL {
                    try? FileManager.default.removeItem(at: dst)
                }
                hlsItemsByID[id] = UnifiedDownloadItem(
                    id: existing.id,
                    backend: .ffmpegHLSMuxer,
                    sourceURL: existing.sourceURL,
                    resolvedFilename: existing.resolvedFilename,
                    destinationURL: nil,
                    state: .cancelled,
                    totalBytes: nil,
                    downloadedBytes: 0,
                    speedBytesPerSecond: 0,
                    etaSeconds: nil,
                    mediaProgressFraction: nil,
                    segments: [],
                    errorMessage: nil,
                    createdAt: existing.createdAt
                )
                publishMergedItems(forceImmediate: true)
                persistHLSHistory()
            }
            return
        }
        try await sdmManager?.cancel(DownloadID(rawValue: id))
    }

    public func retry(_ id: UUID) async throws {
        if let retryInput = hlsRetryInputs[id] {
            hlsItemsByID.removeValue(forKey: id)
            _ = try await enqueueHLSStreamMux(
                manifestURL: retryInput.url,
                variantTitle: retryInput.title,
                sessionContext: retryInput.session
            )
            return
        }
        try await sdmManager?.retry(DownloadID(rawValue: id))
    }

    /// Removes download record & partial temp state ONLY; NEVER deletes a finalized Vault file.
    public func removeFromHistory(_ id: UUID) async throws {
        if hlsItemsByID[id] != nil {
            await hlsWorker.cancelTask(id)
            hlsActiveTasks[id]?.cancel()
            hlsActiveTasks.removeValue(forKey: id)
            hlsItemsByID.removeValue(forKey: id)
            hlsRetryInputs.removeValue(forKey: id)
            publishMergedItems(forceImmediate: true)
            persistHLSHistory()
            return
        }
        try await sdmManager?.remove(DownloadID(rawValue: id))
        sdmSnapshotsByID.removeValue(forKey: id)
        publishMergedItems(forceImmediate: true)
    }

    /// Removes download record AND deletes any finalized Vault file from disk.
    public func deleteWithFinalizedFile(_ id: UUID) async throws {
        let finalizedURL = items.first(where: { $0.id == id })?.destinationURL
        try await removeFromHistory(id)
        if let finalizedURL, FileManager.default.fileExists(atPath: finalizedURL.path) {
            try? FileManager.default.removeItem(at: finalizedURL)
        }
    }

    // MARK: - Private SDMCore Engine Initialization & 6 Hz Coalescing

    private func startSDMCoreEngine() {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("PrismDM", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

            let config = DownloadManagerConfiguration(
                databaseURL: support.appendingPathComponent("downloads.sqlite3"),
                temporaryDirectory: support.appendingPathComponent("PartialDownloads", isDirectory: true),
                maximumActiveDownloads: 3,
                maximumConnectionsPerDownload: 16,
                updateInterval: .milliseconds(100),
                defaultEngine: preferredHTTPBackend,
                urlSessionIdentifier: Self.backgroundSessionIdentifier
            )

            let manager = try DownloadManager(configuration: config)
            self.sdmManager = manager

            sdmObservationTask = Task { @MainActor [weak self] in
                for await update in await manager.updates() {
                    guard let self, !Task.isCancelled else { break }
                    self.ingestSDMSnapshots(update.snapshots)
                }
            }
        } catch {
            engineStartupError = error.localizedDescription
        }
    }

    private func ingestSDMSnapshots(_ snapshots: [DownloadSnapshot]) {
        var hasTerminalTransition = false
        var nextMap: [UUID: UnifiedDownloadItem] = [:]

        for snap in snapshots {
            let uuid = snap.id.rawValue
            let prevState = sdmSnapshotsByID[uuid]?.state
            if prevState != snap.state && (snap.state == .completed || snap.state == .failed || snap.state == .paused || snap.state == .cancelled) {
                hasTerminalTransition = true
            }

            let etaSeconds: Double? = snap.estimatedTimeRemaining.map { dur in
                Double(dur.components.seconds) + Double(dur.components.attoseconds) / 1e18
            }

            let unified = UnifiedDownloadItem(
                id: uuid,
                backend: snap.engine == .libcurl ? .sdmLibcurlRange : .sdmBackgroundSession,
                sourceURL: snap.sourceURL,
                resolvedFilename: snap.filename,
                destinationURL: snap.destinationURL,
                state: snap.state,
                totalBytes: snap.contentLength,
                downloadedBytes: snap.downloadedBytes,
                speedBytesPerSecond: snap.bytesPerSecond,
                etaSeconds: etaSeconds,
                mediaProgressFraction: nil,
                segments: snap.segments,
                errorMessage: snap.error?.message,
                createdAt: snap.createdAt
            )
            nextMap[uuid] = unified

            if snap.state == .completed,
               let destinationURL = snap.destinationURL,
               registeredCompletedIDs.insert(uuid).inserted {
                let isPrivate = incognitoFlagsByTaskID[uuid] ?? false
                registerCompletedFileInVault(
                    fileURL: destinationURL,
                    preferredFilename: snap.filename,
                    sourceURL: snap.sourceURL,
                    isPrivate: isPrivate
                )
            }
        }

        sdmSnapshotsByID = nextMap
        publishMergedItems(forceImmediate: hasTerminalTransition)
    }

    private func handleHLSMuxEvent(_ event: HLSMuxProgressEvent, isIncognito: Bool) {
        guard let existing = hlsItemsByID[event.taskID] else { return }
        let updated = UnifiedDownloadItem(
            id: existing.id,
            backend: .ffmpegHLSMuxer,
            sourceURL: existing.sourceURL,
            resolvedFilename: existing.resolvedFilename,
            destinationURL: event.outputURL ?? existing.destinationURL,
            state: event.state,
            totalBytes: event.state == .completed ? event.downloadedBytes : existing.totalBytes,
            downloadedBytes: event.downloadedBytes > 0 ? event.downloadedBytes : existing.downloadedBytes,
            speedBytesPerSecond: event.speedBytesPerSecond,
            etaSeconds: nil,
            mediaProgressFraction: event.progressFraction ?? existing.mediaProgressFraction,
            segments: [],
            errorMessage: event.errorMessage,
            createdAt: existing.createdAt
        )
        hlsItemsByID[event.taskID] = updated

        let isTerminal = (event.state == .completed || event.state == .failed || event.state == .cancelled)
        publishMergedItems(forceImmediate: isTerminal)

        if isTerminal {
            persistHLSHistory()
        }

        if event.state == .completed,
           let outputURL = event.outputURL,
           registeredCompletedIDs.insert(event.taskID).inserted {
            registerCompletedFileInVault(
                fileURL: outputURL,
                preferredFilename: updated.resolvedFilename,
                sourceURL: updated.sourceURL,
                isPrivate: isIncognito
            )
        }
    }

    /// Strict 6 Hz (`166 ms`) UI coalescing with immediate flush on terminal transitions.
    private func publishMergedItems(forceImmediate: Bool) {
        let now = Date.now
        let elapsed = now.timeIntervalSince(lastPublishTime)

        if forceImmediate || elapsed >= 0.166 {
            deferredFlushTask?.cancel()
            deferredFlushTask = nil
            lastPublishTime = now
            rebuildPublishedItemsArray()
        } else if deferredFlushTask == nil {
            let delayMs = Int(((0.166 - elapsed) * 1000).rounded(.up))
            deferredFlushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(max(16, delayMs)))
                guard let self, !Task.isCancelled else { return }
                self.deferredFlushTask = nil
                self.lastPublishTime = .now
                self.rebuildPublishedItemsArray()
            }
        }
    }

    private func rebuildPublishedItemsArray() {
        var combined = Array(sdmSnapshotsByID.values) + Array(hlsItemsByID.values)
        combined.sort { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive
            }
            return lhs.createdAt > rhs.createdAt
        }
        items = combined
    }

    private func registerCompletedFileInVault(
        fileURL: URL,
        preferredFilename: String,
        sourceURL: URL,
        isPrivate: Bool
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let snapshot = try? await self.vaultService.registerCompletedFile(
                at: fileURL,
                preferredFilename: preferredFilename,
                mimeType: nil,
                sourceURL: sourceURL,
                isPrivate: isPrivate
            ) else { return }

            if let modelContext = self.modelContext {
                let record = VaultItemRecord(
                    id: snapshot.id,
                    relativePath: snapshot.relativePath,
                    displayName: snapshot.displayName,
                    fileExtension: snapshot.fileExtension,
                    mimeType: snapshot.mimeType,
                    byteSize: snapshot.byteSize,
                    kind: snapshot.kind,
                    sourceURLString: snapshot.sourceURLString,
                    isPrivateVault: snapshot.isPrivateVault,
                    createdAt: snapshot.createdAt
                )
                modelContext.insert(record)
                try? modelContext.save()
            }
        }
    }

    private func persistHLSHistory() {
        let records = hlsItemsByID.values.map { item in
            PersistedHLSTaskRecord(
                id: item.id,
                sourceURL: item.sourceURL,
                resolvedFilename: item.resolvedFilename,
                destinationURL: item.destinationURL,
                state: item.isActive ? .paused : item.state,
                downloadedBytes: item.downloadedBytes,
                isIncognito: incognitoFlagsByTaskID[item.id] ?? false,
                errorMessage: item.errorMessage,
                createdAt: item.createdAt
            )
        }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.hlsHistoryKey)
        }
    }

    private func restorePersistedHLSHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.hlsHistoryKey),
              let records = try? JSONDecoder().decode([PersistedHLSTaskRecord].self, from: data) else {
            return
        }
        for rec in records where !rec.isIncognito {
            hlsItemsByID[rec.id] = UnifiedDownloadItem(
                id: rec.id,
                backend: .ffmpegHLSMuxer,
                sourceURL: rec.sourceURL,
                resolvedFilename: rec.resolvedFilename,
                destinationURL: rec.destinationURL,
                state: rec.state,
                totalBytes: rec.state == .completed ? rec.downloadedBytes : nil,
                downloadedBytes: rec.downloadedBytes,
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                mediaProgressFraction: rec.state == .completed ? 1.0 : nil,
                segments: [],
                errorMessage: rec.errorMessage,
                createdAt: rec.createdAt
            )
            if rec.state == .completed {
                registeredCompletedIDs.insert(rec.id)
            }
        }
        rebuildPublishedItemsArray()
    }
}
