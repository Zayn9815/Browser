import Foundation
import Libavcodec
import Libavformat
import Libavutil
import PrismCore
import SDMCore

public struct HLSMuxProgressEvent: Sendable, Equatable {
    public let taskID: UUID
    public let state: DownloadState
    public let downloadedBytes: UInt64
    public let estimatedTotalBytes: UInt64?
    public let isTotalBytesEstimated: Bool
    public let speedBytesPerSecond: UInt64
    public let progressFraction: Double?
    public let segments: [DownloadSegmentSnapshot]
    public let outputURL: URL?
    public let errorMessage: String?

    public init(
        taskID: UUID,
        state: DownloadState,
        downloadedBytes: UInt64,
        estimatedTotalBytes: UInt64? = nil,
        isTotalBytesEstimated: Bool = true,
        speedBytesPerSecond: UInt64,
        progressFraction: Double?,
        segments: [DownloadSegmentSnapshot] = [],
        outputURL: URL? = nil,
        errorMessage: String? = nil
    ) {
        self.taskID = taskID
        self.state = state
        self.downloadedBytes = downloadedBytes
        self.estimatedTotalBytes = estimatedTotalBytes
        self.isTotalBytesEstimated = isTotalBytesEstimated
        self.speedBytesPerSecond = speedBytesPerSecond
        self.progressFraction = progressFraction
        self.segments = segments
        self.outputURL = outputURL
        self.errorMessage = errorMessage
    }
}

public struct HLSParsedSegment: Sendable, Equatable {
    public let index: Int
    public let url: URL
    public let durationSeconds: Double
    public let byteRangeHeader: String?
    public let keyIndex: Int?
    public let initMapIndex: Int?
}

public struct HLSParsedKey: Sendable, Equatable {
    public let method: String
    public let uri: URL?
    public let ivHex: String?
}

public struct HLSParsedMediaPlaylist: Sendable, Equatable {
    public let targetDuration: Double
    public let mediaSequence: Int
    public let totalDurationSeconds: Double
    public let estimatedBandwidthBps: UInt64?
    public let initMaps: [URL]
    public let keys: [HLSParsedKey]
    public let segments: [HLSParsedSegment]
}

public enum HLSPlaylistParser {
    public static func parseMasterBestVariant(
        from text: String,
        baseURL: URL
    ) -> (url: URL, bandwidthBps: UInt64?)? {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        var bestURL: URL?
        var bestBandwidth: UInt64 = 0
        var pendingBandwidth: UInt64?

        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                let attrs = parseAttributes(String(line.dropFirst("#EXT-X-STREAM-INF:".count)))
                if let bwStr = attrs["BANDWIDTH"], let bw = UInt64(bwStr) {
                    pendingBandwidth = bw
                } else {
                    pendingBandwidth = 0
                }
            } else if !line.isEmpty, !line.hasPrefix("#"), let bw = pendingBandwidth {
                if let resolved = URL(string: line, relativeTo: baseURL)?.absoluteURL {
                    if bestURL == nil || bw >= bestBandwidth {
                        bestURL = resolved
                        bestBandwidth = bw
                    }
                }
                pendingBandwidth = nil
            }
        }
        guard let bestURL else { return nil }
        return (bestURL, bestBandwidth > 0 ? bestBandwidth : nil)
    }

    public static func parseMediaPlaylist(
        from text: String,
        baseURL: URL,
        bandwidthHintBps: UInt64? = nil
    ) -> HLSParsedMediaPlaylist {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        var targetDuration: Double = 6.0
        var mediaSequence = 0
        var totalDuration: Double = 0
        var initMaps: [URL] = []
        var keys: [HLSParsedKey] = []
        var currentMapIndex: Int?
        var currentKeyIndex: Int?
        var pendingDuration: Double = 4.0
        var pendingByteRange: String?
        var lastByteRangeEnd: UInt64 = 0
        var segments: [HLSParsedSegment] = []

        for line in lines {
            if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                let raw = String(line.dropFirst("#EXT-X-TARGETDURATION:".count))
                if let d = Double(raw) { targetDuration = max(1.0, d) }
            } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                let raw = String(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count))
                if let seq = Int(raw) { mediaSequence = seq }
            } else if line.hasPrefix("#EXT-X-MAP:") {
                let attrs = parseAttributes(String(line.dropFirst("#EXT-X-MAP:".count)))
                if let uriRaw = attrs["URI"], let resolved = URL(string: uriRaw, relativeTo: baseURL)?.absoluteURL {
                    if let existing = initMaps.firstIndex(of: resolved) {
                        currentMapIndex = existing
                    } else {
                        currentMapIndex = initMaps.count
                        initMaps.append(resolved)
                    }
                }
            } else if line.hasPrefix("#EXT-X-KEY:") {
                let attrs = parseAttributes(String(line.dropFirst("#EXT-X-KEY:".count)))
                let method = (attrs["METHOD"] ?? "NONE").uppercased()
                if method == "NONE" {
                    currentKeyIndex = nil
                } else {
                    let uri = attrs["URI"].flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
                    let key = HLSParsedKey(method: method, uri: uri, ivHex: attrs["IV"])
                    currentKeyIndex = keys.count
                    keys.append(key)
                }
            } else if line.hasPrefix("#EXTINF:") {
                let body = String(line.dropFirst("#EXTINF:".count))
                let durStr = body.split(separator: ",").first.map(String.init) ?? "4.0"
                pendingDuration = max(0.1, Double(durStr) ?? 4.0)
            } else if line.hasPrefix("#EXT-X-BYTERANGE:") {
                let spec = String(line.dropFirst("#EXT-X-BYTERANGE:".count))
                let parts = spec.split(separator: "@")
                if let length = UInt64(parts[0]), length > 0 {
                    let offset: UInt64
                    if parts.count > 1, let explicit = UInt64(parts[1]) {
                        offset = explicit
                    } else {
                        offset = lastByteRangeEnd
                    }
                    let end = offset + length - 1
                    lastByteRangeEnd = end + 1
                    pendingByteRange = "bytes=\(offset)-\(end)"
                }
            } else if !line.isEmpty && !line.hasPrefix("#") {
                if let resolved = URL(string: line, relativeTo: baseURL)?.absoluteURL {
                    let seg = HLSParsedSegment(
                        index: segments.count,
                        url: resolved,
                        durationSeconds: pendingDuration,
                        byteRangeHeader: pendingByteRange,
                        keyIndex: currentKeyIndex,
                        initMapIndex: currentMapIndex
                    )
                    segments.append(seg)
                    totalDuration += pendingDuration
                }
                pendingByteRange = nil
            }
        }

        return HLSParsedMediaPlaylist(
            targetDuration: targetDuration,
            mediaSequence: mediaSequence,
            totalDurationSeconds: totalDuration,
            estimatedBandwidthBps: bandwidthHintBps,
            initMaps: initMaps,
            keys: keys,
            segments: segments
        )
    }

    private static func parseAttributes(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        var key = ""
        var value = ""
        var inKey = true
        var inQuotes = false

        for ch in raw {
            if inKey {
                if ch == "=" {
                    inKey = false
                } else if ch != " " {
                    key.append(ch)
                }
            } else {
                if ch == "\"" {
                    inQuotes.toggle()
                } else if ch == "," && !inQuotes {
                    result[key.uppercased()] = value
                    key = ""
                    value = ""
                    inKey = true
                } else {
                    value.append(ch)
                }
            }
        }
        if !key.isEmpty {
            result[key.uppercased()] = value
        }
        return result
    }
}

private let kAVNoPTSValue: Int64 = Int64(bitPattern: 0x8000_0000_0000_0000)
private let kAVErrorEOF: Int32 = -Int32(bitPattern: (UInt32(0x45)) | (UInt32(0x4F) << 8) | (UInt32(0x46) << 16) | (UInt32(0x20) << 24))

private final class MuxInterruptFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var interrupted = false

    func cancel() {
        lock.lock()
        interrupted = true
        lock.unlock()
    }

    func isInterrupted() -> Bool {
        lock.lock()
        let current = interrupted
        lock.unlock()
        return current
    }
}

private final class ParallelHLSProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private let totalSegments: Int
    private let workerBucketCount: Int
    private let initialEstimatedBytes: UInt64?
    private var completedSegmentMask: [Bool]
    private var completedCount: Int = 0
    private var downloadedBytes: UInt64 = 0
    private var lastEmitTime: Date = .distantPast
    private var lastSampleTime: Date = .now
    private var lastSampleBytes: UInt64 = 0

    init(totalSegments: Int, workerBucketCount: Int, initialEstimatedBytes: UInt64?) {
        self.totalSegments = max(1, totalSegments)
        self.workerBucketCount = max(1, min(workerBucketCount, max(1, totalSegments)))
        self.initialEstimatedBytes = initialEstimatedBytes
        self.completedSegmentMask = Array(repeating: false, count: max(1, totalSegments))
    }

    func seedExistingSegment(index: Int, byteCount: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0, index < completedSegmentMask.count, !completedSegmentMask[index] else { return }
        completedSegmentMask[index] = true
        completedCount += 1
        downloadedBytes &+= byteCount
        lastSampleBytes = downloadedBytes
    }

    func recordCompletedSegment(
        index: Int,
        byteCount: UInt64,
        forceEmit: Bool = false
    ) -> (downloaded: UInt64, estimatedTotal: UInt64?, speed: UInt64, fraction: Double, segments: [DownloadSegmentSnapshot])? {
        lock.lock()
        defer { lock.unlock() }

        if index >= 0, index < completedSegmentMask.count, !completedSegmentMask[index] {
            completedSegmentMask[index] = true
            completedCount += 1
            downloadedBytes &+= byteCount
        }

        let now = Date.now
        let elapsedEmit = now.timeIntervalSince(lastEmitTime)
        let isAllDone = completedCount >= totalSegments
        guard forceEmit || isAllDone || elapsedEmit >= 0.166 else {
            return nil
        }

        let elapsedSpeed = max(now.timeIntervalSince(lastSampleTime), 0.05)
        let deltaBytes = downloadedBytes >= lastSampleBytes ? (downloadedBytes - lastSampleBytes) : 0
        let speed = UInt64(Double(deltaBytes) / elapsedSpeed)
        lastEmitTime = now
        lastSampleTime = now
        lastSampleBytes = downloadedBytes

        let estimatedTotal: UInt64?
        if isAllDone {
            estimatedTotal = max(downloadedBytes, 1)
        } else if completedCount >= 2 && downloadedBytes > 0 {
            let avgPerSeg = Double(downloadedBytes) / Double(completedCount)
            let projected = UInt64((avgPerSeg * Double(totalSegments)).rounded())
            estimatedTotal = max(projected, downloadedBytes + 1)
        } else if let initialEstimatedBytes, initialEstimatedBytes > 0 {
            estimatedTotal = max(initialEstimatedBytes, downloadedBytes + 1)
        } else {
            estimatedTotal = nil
        }

        let fraction = min(max(Double(completedCount) / Double(totalSegments), 0), 0.98)
        let buckets = buildSegmentSnapshots(estimatedTotal: estimatedTotal ?? max(downloadedBytes, 1))
        return (downloadedBytes, estimatedTotal, speed, fraction, buckets)
    }

    private func buildSegmentSnapshots(estimatedTotal: UInt64) -> [DownloadSegmentSnapshot] {
        let total = max(estimatedTotal, UInt64(workerBucketCount))
        var snapshots: [DownloadSegmentSnapshot] = []
        snapshots.reserveCapacity(workerBucketCount)

        for b in 0..<workerBucketCount {
            let segStart = (b * totalSegments) / workerBucketCount
            let segEnd = max(segStart + 1, ((b + 1) * totalSegments) / workerBucketCount)
            let segCount = max(1, segEnd - segStart)
            var doneInBucket = 0
            for idx in segStart..<min(segEnd, completedSegmentMask.count) where completedSegmentMask[idx] {
                doneInBucket += 1
            }

            let byteStart = (UInt64(b) * total) / UInt64(workerBucketCount)
            let byteEnd = b == workerBucketCount - 1
                ? (total - 1)
                : max(byteStart, ((UInt64(b + 1) * total) / UInt64(workerBucketCount)) - 1)
            let bucketWidth = (byteEnd >= byteStart) ? (byteEnd - byteStart + 1) : 1
            let doneBytes = UInt64((Double(doneInBucket) / Double(segCount)) * Double(bucketWidth))
            let nextOffset = byteStart + min(doneBytes, bucketWidth)

            snapshots.append(
                DownloadSegmentSnapshot(
                    ordinal: b,
                    start: byteStart,
                    end: byteEnd,
                    next: nextOffset
                )
            )
        }
        return snapshots
    }
}

private func prismAVIOInterruptCallback(_ opaque: UnsafeMutableRawPointer?) -> Int32 {
    guard let opaque else { return 0 }
    let flag = Unmanaged<MuxInterruptFlag>.fromOpaque(opaque).takeUnretainedValue()
    return flag.isInterrupted() ? 1 : 0
}

private func ffmpegErrorDescription(_ code: Int32) -> String {
    var buffer = [CChar](repeating: 0, count: 256)
    av_strerror(code, &buffer, buffer.count)
    let trimmedBytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: trimmedBytes, as: UTF8.self)
}

/// Two-Stage Parallel Chunked HLS Engine + In-Process `Libavformat`/`Libavcodec` Local Remuxer:
/// 1. Parses `.m3u8` playlist (master/media, `EXT-X-MAP`, `EXT-X-KEY` AES-128, `EXT-X-BYTERANGE`, `BANDWIDTH`).
/// 2. Downloads `.ts`/`.m4s` segments concurrently across N parallel HTTP connections with resume-from-disk & per-segment retries.
/// 3. Remuxes locally via C `Libavformat`/`Libavcodec` (`-c copy`, `aac_adtstoasc`, `+faststart`) at full NVMe disk speed.
public actor FFmpegHLSMuxerWorker {
    private var interruptFlags: [UUID: MuxInterruptFlag] = [:]

    public init() {
        avformat_network_init()
    }

    public func cancelTask(_ id: UUID) {
        interruptFlags[id]?.cancel()
    }

    public nonisolated static func stagingDirectory(for taskID: UUID) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("PrismDM", isDirectory: true)
            .appendingPathComponent("HLSParts", isDirectory: true)
            .appendingPathComponent(taskID.uuidString, isDirectory: true)
    }

    public nonisolated static func removeStagingDirectory(for taskID: UUID) {
        try? FileManager.default.removeItem(at: stagingDirectory(for: taskID))
    }

    public func startRemux(
        taskID: UUID,
        sourceURL: URL,
        outputURL: URL,
        crlfHeaders: String,
        httpHeaders: [String: String] = [:],
        connectionLimit: Int = 8,
        isPrivateContext: Bool = false
    ) -> AsyncStream<HLSMuxProgressEvent> {
        let cancelFlag = MuxInterruptFlag()
        interruptFlags[taskID] = cancelFlag
        let worker = self
        let clampedConnections = min(max(connectionLimit, 1), 16)

        return AsyncStream(bufferingPolicy: .bufferingNewest(12)) { continuation in
            let work = Task.detached(priority: .utility) {
                defer {
                    Task { await worker.clearFlag(for: taskID) }
                    continuation.finish()
                }

                continuation.yield(
                    HLSMuxProgressEvent(
                        taskID: taskID,
                        state: .probing,
                        downloadedBytes: 0,
                        estimatedTotalBytes: nil,
                        isTotalBytesEstimated: true,
                        speedBytesPerSecond: 0,
                        progressFraction: nil
                    )
                )

                do {
                    let isDASH = sourceURL.pathExtension.lowercased() == "mpd"
                    let finalBytes: UInt64

                    if isDASH {
                        // Direct Libavformat remux fallback for non-HLS DASH manifests
                        finalBytes = try Self.executeRemuxBlocking(
                            sourceURLString: sourceURL.absoluteString,
                            outputPath: outputURL.path(percentEncoded: false),
                            crlfHeaders: crlfHeaders,
                            isLocalInput: false,
                            cancelFlag: cancelFlag,
                            onProgress: { bytes, speed, fraction in
                                continuation.yield(
                                    HLSMuxProgressEvent(
                                        taskID: taskID,
                                        state: .downloading,
                                        downloadedBytes: bytes,
                                        estimatedTotalBytes: nil,
                                        isTotalBytesEstimated: true,
                                        speedBytesPerSecond: speed,
                                        progressFraction: fraction
                                    )
                                )
                            }
                        )
                    } else {
                        finalBytes = try await Self.executeParallelHLSAndLocalRemux(
                            taskID: taskID,
                            manifestURL: sourceURL,
                            outputURL: outputURL,
                            httpHeaders: httpHeaders,
                            connectionLimit: clampedConnections,
                            isPrivateContext: isPrivateContext,
                            cancelFlag: cancelFlag,
                            yieldEvent: { event in
                                continuation.yield(event)
                            }
                        )
                    }

                    if cancelFlag.isInterrupted() || Task.isCancelled {
                        try? FileManager.default.removeItem(at: outputURL)
                        continuation.yield(
                            HLSMuxProgressEvent(
                                taskID: taskID,
                                state: .cancelled,
                                downloadedBytes: 0,
                                estimatedTotalBytes: nil,
                                isTotalBytesEstimated: false,
                                speedBytesPerSecond: 0,
                                progressFraction: nil
                            )
                        )
                    } else {
                        Self.removeStagingDirectory(for: taskID)
                        continuation.yield(
                            HLSMuxProgressEvent(
                                taskID: taskID,
                                state: .completed,
                                downloadedBytes: finalBytes,
                                estimatedTotalBytes: finalBytes,
                                isTotalBytesEstimated: false,
                                speedBytesPerSecond: 0,
                                progressFraction: 1.0,
                                outputURL: outputURL
                            )
                        )
                    }
                } catch {
                    try? FileManager.default.removeItem(at: outputURL)
                    let isCancelled = cancelFlag.isInterrupted() || Task.isCancelled
                    if !isCancelled {
                        PrismLogCenter.record(
                            .error,
                            category: .downloader,
                            "HLS parallel download failed (\(sourceURL.host ?? "unknown")): \(error.localizedDescription)",
                            isPrivateContext: isPrivateContext
                        )
                    }
                    continuation.yield(
                        HLSMuxProgressEvent(
                            taskID: taskID,
                            state: isCancelled ? .cancelled : .failed,
                            downloadedBytes: 0,
                            estimatedTotalBytes: nil,
                            isTotalBytesEstimated: false,
                            speedBytesPerSecond: 0,
                            progressFraction: nil,
                            errorMessage: isCancelled ? nil : error.localizedDescription
                        )
                    )
                }
            }

            continuation.onTermination = { _ in
                cancelFlag.cancel()
                work.cancel()
            }
        }
    }

    private func clearFlag(for taskID: UUID) {
        interruptFlags.removeValue(forKey: taskID)
    }

    // MARK: - Stage 1 & 2: Two-Stage Parallel Chunked HLS Downloader

    private static func executeParallelHLSAndLocalRemux(
        taskID: UUID,
        manifestURL: URL,
        outputURL: URL,
        httpHeaders: [String: String],
        connectionLimit: Int,
        isPrivateContext: Bool,
        cancelFlag: MuxInterruptFlag,
        yieldEvent: @escaping @Sendable (HLSMuxProgressEvent) -> Void
    ) async throws -> UInt64 {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.httpMaximumConnectionsPerHost = max(connectionLimit, 8)
        sessionConfig.timeoutIntervalForRequest = 25
        sessionConfig.timeoutIntervalForResource = 300
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: sessionConfig)
        defer { session.finishTasksAndInvalidate() }

        // 1. Fetch & parse playlist (auto-resolve master playlist -> highest-bandwidth variant)
        let firstData = try await fetchBytesWithRetry(
            url: manifestURL,
            headers: httpHeaders,
            byteRange: nil,
            session: session,
            cancelFlag: cancelFlag
        )
        guard let firstText = String(data: firstData, encoding: .utf8) ?? String(data: firstData, encoding: .isoLatin1) else {
            throw NSError(domain: "PrismFFmpegMuxer", code: -10, userInfo: [NSLocalizedDescriptionKey: "Playlist response is not readable UTF-8 text."])
        }

        let mediaPlaylistText: String
        let mediaPlaylistBaseURL: URL
        let bandwidthHint: UInt64?

        if firstText.contains("#EXT-X-STREAM-INF"),
           let variant = HLSPlaylistParser.parseMasterBestVariant(from: firstText, baseURL: manifestURL) {
            let variantData = try await fetchBytesWithRetry(
                url: variant.url,
                headers: httpHeaders,
                byteRange: nil,
                session: session,
                cancelFlag: cancelFlag
            )
            guard let text = String(data: variantData, encoding: .utf8) ?? String(data: variantData, encoding: .isoLatin1) else {
                throw NSError(domain: "PrismFFmpegMuxer", code: -11, userInfo: [NSLocalizedDescriptionKey: "Variant media playlist is unreadable."])
            }
            mediaPlaylistText = text
            mediaPlaylistBaseURL = variant.url
            bandwidthHint = variant.bandwidthBps
        } else {
            mediaPlaylistText = firstText
            mediaPlaylistBaseURL = manifestURL
            bandwidthHint = nil
        }

        let playlist = HLSPlaylistParser.parseMediaPlaylist(
            from: mediaPlaylistText,
            baseURL: mediaPlaylistBaseURL,
            bandwidthHintBps: bandwidthHint
        )
        guard !playlist.segments.isEmpty else {
            throw NSError(domain: "PrismFFmpegMuxer", code: -12, userInfo: [NSLocalizedDescriptionKey: "HLS media playlist contained 0 segments."])
        }

        // Reject FairPlay / SAMPLE-AES DRM keys cleanly
        for key in playlist.keys where key.method != "NONE" && key.method != "AES-128" {
            throw NSError(domain: "PrismFFmpegMuxer", code: -13, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported DRM encryption method (\(key.method)). Only unencrypted or standard AES-128 HLS streams can be downloaded."
            ])
        }

        let stageDir = stagingDirectory(for: taskID)
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)

        // Download EXT-X-MAP init segments and AES-128 keys locally
        var localInitFilenames: [Int: String] = [:]
        for (idx, mapURL) in playlist.initMaps.enumerated() {
            let filename = "init_\(idx).mp4"
            let dst = stageDir.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: dst.path) {
                let data = try await fetchBytesWithRetry(
                    url: mapURL,
                    headers: httpHeaders,
                    byteRange: nil,
                    session: session,
                    cancelFlag: cancelFlag
                )
                try data.write(to: dst, options: .atomic)
            }
            localInitFilenames[idx] = filename
        }

        var localKeyFilenames: [Int: String] = [:]
        for (idx, key) in playlist.keys.enumerated() {
            guard key.method == "AES-128", let keyURL = key.uri else { continue }
            let filename = "key_\(idx).bin"
            let dst = stageDir.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: dst.path) {
                let data = try await fetchBytesWithRetry(
                    url: keyURL,
                    headers: httpHeaders,
                    byteRange: nil,
                    session: session,
                    cancelFlag: cancelFlag
                )
                try data.write(to: dst, options: .atomic)
            }
            localKeyFilenames[idx] = filename
        }

        let initialEstimatedBytes: UInt64? = {
            guard let bw = playlist.estimatedBandwidthBps, bw > 0, playlist.totalDurationSeconds > 0 else {
                return nil
            }
            return UInt64((Double(bw) * playlist.totalDurationSeconds) / 8.0)
        }()

        let tracker = ParallelHLSProgressTracker(
            totalSegments: playlist.segments.count,
            workerBucketCount: min(connectionLimit, max(1, playlist.segments.count)),
            initialEstimatedBytes: initialEstimatedBytes
        )

        // Resume-from-disk: scan already-downloaded segment files so paused tasks resume cleanly
        var pendingSegments: [HLSParsedSegment] = []
        pendingSegments.reserveCapacity(playlist.segments.count)
        let fm = FileManager.default
        for seg in playlist.segments {
            let fileURL = stageDir.appendingPathComponent(Self.segmentFilename(for: seg.index))
            if fm.fileExists(atPath: fileURL.path),
               let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
               let size = (attrs[.size] as? NSNumber)?.uint64Value,
               size > 0 {
                tracker.seedExistingSegment(index: seg.index, byteCount: size)
            } else {
                pendingSegments.append(seg)
            }
        }

        PrismLogCenter.record(
            .info,
            category: .downloader,
            "Parallel HLS started: \(playlist.segments.count) segments (\(pendingSegments.count) pending), \(connectionLimit) workers.",
            isPrivateContext: isPrivateContext
        )

        if let initialSnap = tracker.recordCompletedSegment(index: -1, byteCount: 0, forceEmit: true) {
            yieldEvent(
                HLSMuxProgressEvent(
                    taskID: taskID,
                    state: .downloading,
                    downloadedBytes: initialSnap.downloaded,
                    estimatedTotalBytes: initialSnap.estimatedTotal,
                    isTotalBytesEstimated: true,
                    speedBytesPerSecond: 0,
                    progressFraction: initialSnap.fraction,
                    segments: initialSnap.segments
                )
            )
        }

        // 2. Concurrent N-worker segment download pool
        if !pendingSegments.isEmpty {
            try await withThrowingTaskGroup(of: Void.self) { group in
                var nextIdx = 0
                let initialBatch = min(connectionLimit, pendingSegments.count)

                for _ in 0..<initialBatch {
                    let seg = pendingSegments[nextIdx]
                    nextIdx += 1
                    group.addTask {
                        try await Self.downloadSingleSegment(
                            seg,
                            stageDir: stageDir,
                            headers: httpHeaders,
                            session: session,
                            cancelFlag: cancelFlag,
                            tracker: tracker,
                            taskID: taskID,
                            yieldEvent: yieldEvent
                        )
                    }
                }

                while try await group.next() != nil {
                    if cancelFlag.isInterrupted() || Task.isCancelled {
                        group.cancelAll()
                        throw CancellationError()
                    }
                    if nextIdx < pendingSegments.count {
                        let seg = pendingSegments[nextIdx]
                        nextIdx += 1
                        group.addTask {
                            try await Self.downloadSingleSegment(
                                seg,
                                stageDir: stageDir,
                                headers: httpHeaders,
                                session: session,
                                cancelFlag: cancelFlag,
                                tracker: tracker,
                                taskID: taskID,
                                yieldEvent: yieldEvent
                            )
                        }
                    }
                }
            }
        }

        if cancelFlag.isInterrupted() || Task.isCancelled {
            throw CancellationError()
        }

        // 3. Generate local.m3u8 referencing local files and remux at NVMe disk speed
        let localPlaylistURL = stageDir.appendingPathComponent("local.m3u8")
        let localM3U8 = Self.buildLocalPlaylist(
            from: playlist,
            localInitFilenames: localInitFilenames,
            localKeyFilenames: localKeyFilenames
        )
        try localM3U8.write(to: localPlaylistURL, atomically: true, encoding: .utf8)

        if let finalizingSnap = tracker.recordCompletedSegment(index: -1, byteCount: 0, forceEmit: true) {
            yieldEvent(
                HLSMuxProgressEvent(
                    taskID: taskID,
                    state: .finalizing,
                    downloadedBytes: finalizingSnap.downloaded,
                    estimatedTotalBytes: finalizingSnap.downloaded,
                    isTotalBytesEstimated: false,
                    speedBytesPerSecond: 0,
                    progressFraction: 0.99,
                    segments: finalizingSnap.segments
                )
            )
        }

        return try Self.executeRemuxBlocking(
            sourceURLString: localPlaylistURL.path(percentEncoded: false),
            outputPath: outputURL.path(percentEncoded: false),
            crlfHeaders: "",
            isLocalInput: true,
            cancelFlag: cancelFlag,
            onProgress: { _, _, _ in }
        )
    }

    private static func downloadSingleSegment(
        _ seg: HLSParsedSegment,
        stageDir: URL,
        headers: [String: String],
        session: URLSession,
        cancelFlag: MuxInterruptFlag,
        tracker: ParallelHLSProgressTracker,
        taskID: UUID,
        yieldEvent: @Sendable (HLSMuxProgressEvent) -> Void
    ) async throws {
        if cancelFlag.isInterrupted() || Task.isCancelled {
            throw CancellationError()
        }
        let data = try await fetchBytesWithRetry(
            url: seg.url,
            headers: headers,
            byteRange: seg.byteRangeHeader,
            session: session,
            cancelFlag: cancelFlag
        )
        if cancelFlag.isInterrupted() || Task.isCancelled {
            throw CancellationError()
        }
        let dst = stageDir.appendingPathComponent(segmentFilename(for: seg.index))
        try data.write(to: dst, options: .atomic)

        if let snap = tracker.recordCompletedSegment(index: seg.index, byteCount: UInt64(data.count)) {
            yieldEvent(
                HLSMuxProgressEvent(
                    taskID: taskID,
                    state: .downloading,
                    downloadedBytes: snap.downloaded,
                    estimatedTotalBytes: snap.estimatedTotal,
                    isTotalBytesEstimated: true,
                    speedBytesPerSecond: snap.speed,
                    progressFraction: snap.fraction,
                    segments: snap.segments
                )
            )
        }
    }

    private static func fetchBytesWithRetry(
        url: URL,
        headers: [String: String],
        byteRange: String?,
        session: URLSession,
        cancelFlag: MuxInterruptFlag,
        maxAttempts: Int = 3
    ) async throws -> Data {
        var lastError: Error = NSError(domain: "PrismFFmpegMuxer", code: -20, userInfo: [NSLocalizedDescriptionKey: "Network request failed."])
        for attempt in 1...maxAttempts {
            if cancelFlag.isInterrupted() || Task.isCancelled {
                throw CancellationError()
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            for (k, v) in headers {
                request.setValue(v, forHTTPHeaderField: k)
            }
            if let byteRange {
                request.setValue(byteRange, forHTTPHeaderField: "Range")
            }

            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse {
                    guard (200...299).contains(http.statusCode) else {
                        let statusErr = NSError(
                            domain: "PrismFFmpegMuxer",
                            code: http.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) fetching segment"]
                        )
                        if http.statusCode == 403 || http.statusCode == 404 || http.statusCode == 410 {
                            throw statusErr
                        }
                        lastError = statusErr
                        if attempt < maxAttempts {
                            try? await Task.sleep(for: .milliseconds(250 * attempt))
                        }
                        continue
                    }
                }
                return data
            } catch {
                if cancelFlag.isInterrupted() || Task.isCancelled {
                    throw CancellationError()
                }
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(for: .milliseconds(250 * attempt))
                }
            }
        }
        throw lastError
    }

    private static func segmentFilename(for index: Int) -> String {
        String(format: "seg_%06d.part", index)
    }

    private static func buildLocalPlaylist(
        from playlist: HLSParsedMediaPlaylist,
        localInitFilenames: [Int: String],
        localKeyFilenames: [Int: String]
    ) -> String {
        var lines: [String] = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-TARGETDURATION:\(Int(ceil(playlist.targetDuration)))",
            "#EXT-X-MEDIA-SEQUENCE:\(playlist.mediaSequence)",
            "#EXT-X-PLAYLIST-TYPE:VOD",
        ]

        var emittedMapIdx: Int?
        var emittedKeyIdx: Int?

        for seg in playlist.segments {
            if let mapIdx = seg.initMapIndex, mapIdx != emittedMapIdx, let fname = localInitFilenames[mapIdx] {
                lines.append("#EXT-X-MAP:URI=\"\(fname)\"")
                emittedMapIdx = mapIdx
            }
            if seg.keyIndex != emittedKeyIdx {
                if let keyIdx = seg.keyIndex, keyIdx < playlist.keys.count {
                    let key = playlist.keys[keyIdx]
                    if key.method == "AES-128", let fname = localKeyFilenames[keyIdx] {
                        if let iv = key.ivHex, !iv.isEmpty {
                            lines.append("#EXT-X-KEY:METHOD=AES-128,URI=\"\(fname)\",IV=\(iv)")
                        } else {
                            lines.append("#EXT-X-KEY:METHOD=AES-128,URI=\"\(fname)\"")
                        }
                    }
                } else {
                    lines.append("#EXT-X-KEY:METHOD=NONE")
                }
                emittedKeyIdx = seg.keyIndex
            }
            lines.append(String(format: "#EXTINF:%.3f,", seg.durationSeconds))
            lines.append(segmentFilename(for: seg.index))
        }

        lines.append("#EXT-X-ENDLIST")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Stage 3: In-Process Libavformat / Libavcodec Local Stream-Copy Remuxer

    private static func executeRemuxBlocking(
        sourceURLString: String,
        outputPath: String,
        crlfHeaders: String,
        isLocalInput: Bool,
        cancelFlag: MuxInterruptFlag,
        onProgress: (_ writtenBytes: UInt64, _ speedBytesPerSec: UInt64, _ fraction: Double?) -> Void
    ) throws -> UInt64 {
        var inCtx: UnsafeMutablePointer<AVFormatContext>? = avformat_alloc_context()
        guard let allocatedIn = inCtx else {
            throw NSError(domain: "PrismFFmpegMuxer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate AVFormatContext."])
        }

        allocatedIn.pointee.interrupt_callback = AVIOInterruptCB(
            callback: prismAVIOInterruptCallback,
            opaque: Unmanaged.passUnretained(cancelFlag).toOpaque()
        )

        var inOpts: OpaquePointer?
        defer {
            if inOpts != nil { av_dict_free(&inOpts) }
            if inCtx != nil { avformat_close_input(&inCtx) }
        }

        if isLocalInput {
            av_dict_set(&inOpts, "allowed_extensions", "ALL", 0)
            av_dict_set(&inOpts, "protocol_whitelist", "file,crypto,hls,concat,data", 0)
        } else {
            if !crlfHeaders.isEmpty {
                av_dict_set(&inOpts, "headers", crlfHeaders, 0)
            }
            av_dict_set(&inOpts, "reconnect", "1", 0)
            av_dict_set(&inOpts, "reconnect_streamed", "1", 0)
            av_dict_set(&inOpts, "reconnect_delay_max", "5", 0)
            av_dict_set(&inOpts, "rw_timeout", "15000000", 0)
            av_dict_set(&inOpts, "protocol_whitelist", "file,http,https,tcp,tls,crypto,hls,concat,data", 0)
        }

        let openErr = avformat_open_input(&inCtx, sourceURLString, nil, &inOpts)
        guard openErr >= 0, let input = inCtx else {
            throw NSError(domain: "PrismFFmpegMuxer", code: Int(openErr), userInfo: [
                NSLocalizedDescriptionKey: "Failed to open stream for remux: \(ffmpegErrorDescription(openErr))"
            ])
        }

        let infoErr = avformat_find_stream_info(input, nil)
        guard infoErr >= 0 else {
            throw NSError(domain: "PrismFFmpegMuxer", code: Int(infoErr), userInfo: [
                NSLocalizedDescriptionKey: "Unable to read stream info: \(ffmpegErrorDescription(infoErr))"
            ])
        }

        var outCtx: UnsafeMutablePointer<AVFormatContext>?
        let allocOutErr = avformat_alloc_output_context2(&outCtx, nil, "mp4", outputPath)
        guard allocOutErr >= 0, let output = outCtx else {
            throw NSError(domain: "PrismFFmpegMuxer", code: Int(allocOutErr), userInfo: [
                NSLocalizedDescriptionKey: "Failed to allocate MP4 output context: \(ffmpegErrorDescription(allocOutErr))"
            ])
        }

        var bsfContexts: [Int: UnsafeMutablePointer<AVBSFContext>] = [:]
        defer {
            for (_, bsfPtr) in bsfContexts {
                var optionalPtr: UnsafeMutablePointer<AVBSFContext>? = bsfPtr
                av_bsf_free(&optionalPtr)
            }
            let oformatFlags = output.pointee.oformat?.pointee.flags ?? 0
            if (oformatFlags & AVFMT_NOFILE) == 0, output.pointee.pb != nil {
                avio_closep(&output.pointee.pb)
            }
            avformat_free_context(output)
        }

        let streamCount = Int(input.pointee.nb_streams)
        var streamMapping = [Int32](repeating: -1, count: streamCount)
        var outStreamIndex: Int32 = 0

        for i in 0..<streamCount {
            guard let inStream = input.pointee.streams[i],
                  let codecPar = inStream.pointee.codecpar else { continue }
            let mediaType = codecPar.pointee.codec_type
            guard mediaType == AVMEDIA_TYPE_VIDEO || mediaType == AVMEDIA_TYPE_AUDIO else {
                continue
            }

            guard let outStream = avformat_new_stream(output, nil) else {
                throw NSError(domain: "PrismFFmpegMuxer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate output stream."])
            }

            let copyErr = avcodec_parameters_copy(outStream.pointee.codecpar, codecPar)
            guard copyErr >= 0 else {
                throw NSError(domain: "PrismFFmpegMuxer", code: Int(copyErr), userInfo: [
                    NSLocalizedDescriptionKey: "Codec parameter copy failed: \(ffmpegErrorDescription(copyErr))"
                ])
            }
            outStream.pointee.codecpar.pointee.codec_tag = 0

            if mediaType == AVMEDIA_TYPE_AUDIO && codecPar.pointee.codec_id == AV_CODEC_ID_AAC,
               let filter = av_bsf_get_by_name("aac_adtstoasc") {
                var bsf: UnsafeMutablePointer<AVBSFContext>?
                if av_bsf_alloc(filter, &bsf) >= 0, let allocatedBSF = bsf {
                    avcodec_parameters_copy(allocatedBSF.pointee.par_in, codecPar)
                    allocatedBSF.pointee.time_base_in = inStream.pointee.time_base
                    if av_bsf_init(allocatedBSF) >= 0 {
                        avcodec_parameters_copy(outStream.pointee.codecpar, allocatedBSF.pointee.par_out)
                        outStream.pointee.codecpar.pointee.codec_tag = 0
                        bsfContexts[i] = allocatedBSF
                    } else {
                        var toFree: UnsafeMutablePointer<AVBSFContext>? = allocatedBSF
                        av_bsf_free(&toFree)
                    }
                }
            }

            streamMapping[i] = outStreamIndex
            outStreamIndex += 1
        }

        guard outStreamIndex > 0 else {
            throw NSError(domain: "PrismFFmpegMuxer", code: -3, userInfo: [NSLocalizedDescriptionKey: "No supported video or audio streams found in playlist."])
        }

        let outFlags = output.pointee.oformat?.pointee.flags ?? 0
        if (outFlags & AVFMT_NOFILE) == 0 {
            let ioErr = avio_open(&output.pointee.pb, outputPath, AVIO_FLAG_WRITE)
            guard ioErr >= 0 else {
                throw NSError(domain: "PrismFFmpegMuxer", code: Int(ioErr), userInfo: [
                    NSLocalizedDescriptionKey: "Cannot open output MP4 file: \(ffmpegErrorDescription(ioErr))"
                ])
            }
        }

        var outOpts: OpaquePointer?
        defer { if outOpts != nil { av_dict_free(&outOpts) } }
        av_dict_set(&outOpts, "movflags", "+faststart", 0)

        let headerErr = avformat_write_header(output, &outOpts)
        guard headerErr >= 0 else {
            throw NSError(domain: "PrismFFmpegMuxer", code: Int(headerErr), userInfo: [
                NSLocalizedDescriptionKey: "Failed to write MP4 header: \(ffmpegErrorDescription(headerErr))"
            ])
        }

        let totalDurationSeconds: Double? = input.pointee.duration > 0
            ? Double(input.pointee.duration) / Double(AV_TIME_BASE)
            : nil

        var packet: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
        guard let pkt = packet else {
            throw NSError(domain: "PrismFFmpegMuxer", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate AVPacket."])
        }
        defer { av_packet_free(&packet) }

        var writtenBytes: UInt64 = 0
        var lastSampleTime = Date.now
        var lastSampleBytes: UInt64 = 0

        while !cancelFlag.isInterrupted() {
            let readErr = av_read_frame(input, pkt)
            if readErr < 0 {
                if readErr == kAVErrorEOF {
                    break
                }
                throw NSError(domain: "PrismFFmpegMuxer", code: Int(readErr), userInfo: [
                    NSLocalizedDescriptionKey: "Stream read failed: \(ffmpegErrorDescription(readErr))"
                ])
            }

            let inIdx = Int(pkt.pointee.stream_index)
            guard inIdx >= 0, inIdx < streamMapping.count, streamMapping[inIdx] >= 0 else {
                av_packet_unref(pkt)
                continue
            }

            let outIdx = streamMapping[inIdx]
            guard let inStream = input.pointee.streams[inIdx],
                  let outStream = output.pointee.streams[Int(outIdx)] else {
                av_packet_unref(pkt)
                continue
            }

            let packetPTS = pkt.pointee.pts != kAVNoPTSValue ? pkt.pointee.pts : pkt.pointee.dts
            let inTimeBase = inStream.pointee.time_base

            if let bsf = bsfContexts[inIdx] {
                if av_bsf_send_packet(bsf, pkt) >= 0 {
                    while av_bsf_receive_packet(bsf, pkt) >= 0 {
                        let pktSize = max(0, Int(pkt.pointee.size))
                        writtenBytes &+= UInt64(pktSize)
                        pkt.pointee.stream_index = outIdx
                        av_packet_rescale_ts(pkt, bsf.pointee.time_base_out, outStream.pointee.time_base)
                        pkt.pointee.pos = -1
                        let writeErr = av_interleaved_write_frame(output, pkt)
                        av_packet_unref(pkt)
                        if writeErr < 0 {
                            throw NSError(domain: "PrismFFmpegMuxer", code: Int(writeErr), userInfo: [
                                NSLocalizedDescriptionKey: "MP4 write failed: \(ffmpegErrorDescription(writeErr))"
                            ])
                        }
                    }
                } else {
                    av_packet_unref(pkt)
                }
            } else {
                let pktSize = max(0, Int(pkt.pointee.size))
                writtenBytes &+= UInt64(pktSize)
                pkt.pointee.stream_index = outIdx
                av_packet_rescale_ts(pkt, inTimeBase, outStream.pointee.time_base)
                pkt.pointee.pos = -1
                let writeErr = av_interleaved_write_frame(output, pkt)
                av_packet_unref(pkt)
                if writeErr < 0 {
                    throw NSError(domain: "PrismFFmpegMuxer", code: Int(writeErr), userInfo: [
                        NSLocalizedDescriptionKey: "MP4 write failed: \(ffmpegErrorDescription(writeErr))"
                    ])
                }
            }

            let now = Date.now
            let elapsed = now.timeIntervalSince(lastSampleTime)
            if elapsed >= 0.166 {
                let deltaBytes = writtenBytes >= lastSampleBytes ? (writtenBytes - lastSampleBytes) : 0
                let speed = UInt64(Double(deltaBytes) / max(elapsed, 0.05))
                var fraction: Double?
                if let totalDur = totalDurationSeconds, totalDur > 0, packetPTS != kAVNoPTSValue, inTimeBase.den > 0 {
                    let currentSec = Double(packetPTS) * (Double(inTimeBase.num) / Double(inTimeBase.den))
                    fraction = min(max(currentSec / totalDur, 0), 0.99)
                }
                onProgress(writtenBytes, speed, fraction)
                lastSampleTime = now
                lastSampleBytes = writtenBytes
            }
        }

        if !cancelFlag.isInterrupted() {
            let trailerErr = av_write_trailer(output)
            if trailerErr < 0 {
                throw NSError(domain: "PrismFFmpegMuxer", code: Int(trailerErr), userInfo: [
                    NSLocalizedDescriptionKey: "Failed to finalize MP4 trailer: \(ffmpegErrorDescription(trailerErr))"
                ])
            }
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath),
           let size = (attrs[.size] as? NSNumber)?.uint64Value, size > 0 {
            return size
        }
        return writtenBytes
    }
}
