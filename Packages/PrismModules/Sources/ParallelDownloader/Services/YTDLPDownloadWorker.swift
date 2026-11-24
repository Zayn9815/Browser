import Foundation
import PrismCore
import SDMCore
import YTDLP

public struct YTDLPProgressEvent: Sendable {
    public let taskID: UUID
    public let state: DownloadState
    public let backend: PrismTransferBackendKind
    public let downloadedBytes: UInt64
    public let totalBytes: UInt64?
    public let isTotalBytesEstimated: Bool
    public let speedBytesPerSecond: UInt64
    public let progressFraction: Double
    public let segments: [DownloadSegmentSnapshot]
    public let finalFileURL: URL?
    public let errorMessage: String?

    public init(
        taskID: UUID,
        state: DownloadState,
        backend: PrismTransferBackendKind,
        downloadedBytes: UInt64,
        totalBytes: UInt64?,
        isTotalBytesEstimated: Bool,
        speedBytesPerSecond: UInt64,
        progressFraction: Double,
        segments: [DownloadSegmentSnapshot] = [],
        finalFileURL: URL? = nil,
        errorMessage: String? = nil
    ) {
        self.taskID = taskID
        self.state = state
        self.backend = backend
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.isTotalBytesEstimated = isTotalBytesEstimated
        self.speedBytesPerSecond = speedBytesPerSecond
        self.progressFraction = progressFraction
        self.segments = segments
        self.finalFileURL = finalFileURL
        self.errorMessage = errorMessage
    }
}

public struct YTDLPParsedProgressLine: Sendable, Equatable {
    public let fraction: Double
    public let totalBytes: UInt64?
    public let speedBytesPerSecond: UInt64
}

/// Executes `yt-dlp` downloads using a two-tier strategy:
/// 1. **Fast Path (`yt-dlp + Parallel`)**: Multi-connection parallel byte-range download of resolved direct streams
///    + local in-process `FFmpegDualStreamMuxer` (`-c copy`, `+faststart`).
/// 2. **Direct Path (`yt-dlp Direct`)**: Automatic fallback or explicit direct execution via `YTDLP.shared.run("--newline", ...)`
///    with live stdout progress parsing and instant `YTDLP.shared.cancel(id:)` support.
public actor YTDLPDownloadWorker {
    private var cancelledTaskIDs: Set<UUID> = []

    public init() {}

    public func cancel(taskID: UUID) {
        cancelledTaskIDs.insert(taskID)
        YTDLP.shared.cancel(id: taskID.uuidString)
    }

    public func startDownload(
        taskID: UUID,
        mediaInfo: YTDLPMediaInfo,
        format: YTDLPFormatOption,
        preferDirectYTDLP: Bool,
        outputDirectory: URL,
        preferredFilename: String,
        connectionLimit: Int,
        sessionContext: BrowserSessionContext?
    ) -> AsyncStream<YTDLPProgressEvent> {
        cancelledTaskIDs.remove(taskID)
        let isPrivate = sessionContext?.isIncognito ?? false

        return AsyncStream { continuation in
            let runner = Task.detached(priority: .userInitiated) {
                let canUseFastPath = !preferDirectYTDLP && format.supportsParallelFastPath

                if canUseFastPath {
                    do {
                        let finalURL = try await Self.executeParallelFastPath(
                            taskID: taskID,
                            format: format,
                            outputDirectory: outputDirectory,
                            preferredFilename: preferredFilename,
                            connectionLimit: max(1, min(16, connectionLimit)),
                            sessionContext: sessionContext,
                            isCancelled: { await self.isCancelled(taskID) },
                            yield: { continuation.yield($0) }
                        )
                        let fileSize = (try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
                        continuation.yield(YTDLPProgressEvent(
                            taskID: taskID,
                            state: .completed,
                            backend: .ytdlpParallel,
                            downloadedBytes: fileSize,
                            totalBytes: fileSize > 0 ? fileSize : format.estimatedBytes,
                            isTotalBytesEstimated: false,
                            speedBytesPerSecond: 0,
                            progressFraction: 1.0,
                            finalFileURL: finalURL
                        ))
                        continuation.finish()
                        return
                    } catch is CancellationError {
                        continuation.yield(YTDLPProgressEvent(
                            taskID: taskID,
                            state: .cancelled,
                            backend: .ytdlpParallel,
                            downloadedBytes: 0,
                            totalBytes: format.estimatedBytes,
                            isTotalBytesEstimated: true,
                            speedBytesPerSecond: 0,
                            progressFraction: 0
                        ))
                        continuation.finish()
                        return
                    } catch {
                        PrismLogCenter.record(
                            .warning,
                            category: .downloader,
                            "yt-dlp Parallel fast path fell back to Direct yt-dlp: \(error.localizedDescription)",
                            isPrivateContext: isPrivate
                        )
                    }
                }

                // Direct yt-dlp execution (explicit or automatic fallback)
                do {
                    let finalURL = try await Self.executeDirectYTDLP(
                        taskID: taskID,
                        sourceURL: mediaInfo.sourceURL,
                        format: format,
                        outputDirectory: outputDirectory,
                        preferredFilename: preferredFilename,
                        sessionContext: sessionContext,
                        yield: { continuation.yield($0) }
                    )
                    let fileSize = (try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
                    continuation.yield(YTDLPProgressEvent(
                        taskID: taskID,
                        state: .completed,
                        backend: .ytdlpDirect,
                        downloadedBytes: fileSize,
                        totalBytes: fileSize > 0 ? fileSize : format.estimatedBytes,
                        isTotalBytesEstimated: false,
                        speedBytesPerSecond: 0,
                        progressFraction: 1.0,
                        finalFileURL: finalURL
                    ))
                } catch is CancellationError {
                    continuation.yield(YTDLPProgressEvent(
                        taskID: taskID,
                        state: .cancelled,
                        backend: .ytdlpDirect,
                        downloadedBytes: 0,
                        totalBytes: format.estimatedBytes,
                        isTotalBytesEstimated: true,
                        speedBytesPerSecond: 0,
                        progressFraction: 0
                    ))
                } catch {
                    PrismLogCenter.record(
                        .error,
                        category: .downloader,
                        "yt-dlp Direct download failed: \(error.localizedDescription)",
                        isPrivateContext: isPrivate
                    )
                    continuation.yield(YTDLPProgressEvent(
                        taskID: taskID,
                        state: .failed,
                        backend: .ytdlpDirect,
                        downloadedBytes: 0,
                        totalBytes: format.estimatedBytes,
                        isTotalBytesEstimated: true,
                        speedBytesPerSecond: 0,
                        progressFraction: 0,
                        errorMessage: error.localizedDescription
                    ))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                runner.cancel()
                YTDLP.shared.cancel(id: taskID.uuidString)
            }
        }
    }

    private func isCancelled(_ taskID: UUID) -> Bool {
        cancelledTaskIDs.contains(taskID)
    }

    // MARK: - Stage 1: Parallel Multi-Range Fast Path + Local FFmpegKit Mux

    private static func executeParallelFastPath(
        taskID: UUID,
        format: YTDLPFormatOption,
        outputDirectory: URL,
        preferredFilename: String,
        connectionLimit: Int,
        sessionContext: BrowserSessionContext?,
        isCancelled: @escaping @Sendable () async -> Bool,
        yield: @escaping @Sendable (YTDLPProgressEvent) -> Void
    ) async throws -> URL {
        let fm = FileManager.default
        let stageDir = fm.temporaryDirectory
            .appendingPathComponent("PrismYTDLPStage", isDirectory: true)
            .appendingPathComponent(taskID.uuidString, isDirectory: true)
        try fm.createDirectory(at: stageDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stageDir) }

        var headers = format.httpHeaders
        if let ua = sessionContext?.userAgent, !ua.isEmpty, headers["User-Agent"] == nil {
            headers["User-Agent"] = ua
        }
        if let ref = sessionContext?.pageReferer, !ref.isEmpty, headers["Referer"] == nil {
            headers["Referer"] = ref
        }
        if let cookie = sessionContext?.cookieHeader, !cookie.isEmpty, headers["Cookie"] == nil {
            headers["Cookie"] = cookie
        }

        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = max(connectionLimit, 8)
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        yield(YTDLPProgressEvent(
            taskID: taskID,
            state: .probing,
            backend: .ytdlpParallel,
            downloadedBytes: 0,
            totalBytes: format.estimatedBytes,
            isTotalBytesEstimated: true,
            speedBytesPerSecond: 0,
            progressFraction: 0
        ))

        let targetFinalURL = uniqueDestinationURL(in: outputDirectory, filename: preferredFilename)

        if format.isAudioOnly {
            guard let audioURL = format.audioURL ?? format.videoURL else {
                throw YTDLPExtractorError.noPlayableFormats
            }
            let audioFile = stageDir.appendingPathComponent("audio.\(format.containerExt)")
            try await downloadURLParallel(
                url: audioURL,
                to: audioFile,
                headers: headers,
                connections: connectionLimit,
                session: session,
                taskID: taskID,
                byteOffsetForDisplay: 0,
                combinedTotalHint: format.estimatedBytes,
                isCancelled: isCancelled,
                yield: yield
            )
            try fm.moveItem(at: audioFile, to: targetFinalURL)
            return targetFinalURL
        }

        guard let videoURL = format.videoURL else {
            throw YTDLPExtractorError.noPlayableFormats
        }

        let videoStage = stageDir.appendingPathComponent("video.part")
        let videoSize = try await probeContentLength(url: videoURL, headers: headers, session: session)
        let audioSize: UInt64?
        if let audioURL = format.audioURL {
            audioSize = try await probeContentLength(url: audioURL, headers: headers, session: session)
        } else {
            audioSize = nil
        }

        let combinedTotal: UInt64? = {
            if let v = videoSize {
                return v + (audioSize ?? 0)
            }
            return format.estimatedBytes
        }()

        try await downloadURLParallel(
            url: videoURL,
            to: videoStage,
            headers: headers,
            connections: connectionLimit,
            session: session,
            taskID: taskID,
            byteOffsetForDisplay: 0,
            combinedTotalHint: combinedTotal,
            isCancelled: isCancelled,
            yield: yield
        )

        if let audioURL = format.audioURL {
            let audioStage = stageDir.appendingPathComponent("audio.part")
            let vDone = (try? videoStage.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? (videoSize ?? 0)
            try await downloadURLParallel(
                url: audioURL,
                to: audioStage,
                headers: headers,
                connections: max(2, connectionLimit / 2),
                session: session,
                taskID: taskID,
                byteOffsetForDisplay: vDone,
                combinedTotalHint: combinedTotal,
                isCancelled: isCancelled,
                yield: yield
            )

            if await isCancelled() || Task.isCancelled { throw CancellationError() }

            yield(YTDLPProgressEvent(
                taskID: taskID,
                state: .finalizing,
                backend: .ytdlpParallel,
                downloadedBytes: combinedTotal ?? vDone,
                totalBytes: combinedTotal,
                isTotalBytesEstimated: false,
                speedBytesPerSecond: 0,
                progressFraction: 0.98
            ))

            _ = try FFmpegDualStreamMuxer.remux(
                videoFileURL: videoStage,
                audioFileURL: audioStage,
                outputURL: targetFinalURL
            )
            return targetFinalURL
        } else {
            try fm.moveItem(at: videoStage, to: targetFinalURL)
            return targetFinalURL
        }
    }

    private static func probeContentLength(
        url: URL,
        headers: [String: String],
        session: URLSession
    ) async throws -> UInt64? {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return nil }
        if http.statusCode == 206,
           let cr = http.value(forHTTPHeaderField: "Content-Range"),
           let slash = cr.lastIndex(of: "/"),
           let total = UInt64(cr[cr.index(after: slash)...].trimmingCharacters(in: .whitespaces)) {
            return total
        }
        if let cl = http.value(forHTTPHeaderField: "Content-Length"), let parsed = UInt64(cl), parsed > 1 {
            return parsed
        }
        return nil
    }

    private static func downloadURLParallel(
        url: URL,
        to destinationURL: URL,
        headers: [String: String],
        connections: Int,
        session: URLSession,
        taskID: UUID,
        byteOffsetForDisplay: UInt64,
        combinedTotalHint: UInt64?,
        isCancelled: @escaping @Sendable () async -> Bool,
        yield: @escaping @Sendable (YTDLPProgressEvent) -> Void
    ) async throws {
        let totalLength = try await probeContentLength(url: url, headers: headers, session: session)
        let workerCount = (totalLength != nil && (totalLength ?? 0) >= 2 * 1024 * 1024) ? max(1, min(16, connections)) : 1

        if workerCount == 1 || totalLength == nil {
            var req = URLRequest(url: url)
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            let (tempURL, resp) = try await session.download(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw NSError(domain: "PrismYTDLP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
            }
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            return
        }

        let total = totalLength!
        let chunkSize = (total + UInt64(workerCount) - 1) / UInt64(workerCount)
        let ranges: [(Int, UInt64, UInt64)] = (0..<workerCount).compactMap { idx in
            let start = UInt64(idx) * chunkSize
            guard start < total else { return nil }
            let end = min(total - 1, start + chunkSize - 1)
            return (idx, start, end)
        }

        let partDir = destinationURL.deletingLastPathComponent()
            .appendingPathComponent("chunks_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: partDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: partDir) }

        let tracker = ChunkProgressBox(ranges: ranges, displayOffset: byteOffsetForDisplay, combinedTotal: combinedTotalHint ?? (byteOffsetForDisplay + total))

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (idx, start, end) in ranges {
                group.addTask {
                    if await isCancelled() || Task.isCancelled { throw CancellationError() }
                    var req = URLRequest(url: url)
                    req.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

                    let partFile = partDir.appendingPathComponent("part_\(idx).bin")
                    let (bytesStream, resp) = try await session.bytes(for: req)
                    if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw NSError(domain: "PrismYTDLP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) on range \(idx)"])
                    }
                    FileManager.default.createFile(atPath: partFile.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: partFile)
                    defer { try? handle.close() }

                    var buffer = Data()
                    buffer.reserveCapacity(128 * 1024)

                    for try await byte in bytesStream {
                        buffer.append(byte)
                        if buffer.count >= 64 * 1024 {
                            if await isCancelled() || Task.isCancelled { throw CancellationError() }
                            try handle.write(contentsOf: buffer)
                            let added = UInt64(buffer.count)
                            buffer.removeAll(keepingCapacity: true)
                            if let ev = tracker.record(chunkIndex: idx, addedBytes: added, taskID: taskID) {
                                yield(ev)
                            }
                        }
                    }
                    if !buffer.isEmpty {
                        try handle.write(contentsOf: buffer)
                        let added = UInt64(buffer.count)
                        if let ev = tracker.record(chunkIndex: idx, addedBytes: added, taskID: taskID, force: true) {
                            yield(ev)
                        }
                    }
                }
            }
            try await group.waitForAll()
        }

        // Assemble sequential chunks into destinationURL
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: destinationURL)
        defer { try? outHandle.close() }
        for (idx, _, _) in ranges {
            let partFile = partDir.appendingPathComponent("part_\(idx).bin")
            let inHandle = try FileHandle(forReadingFrom: partFile)
            defer { try? inHandle.close() }
            while let chunk = try inHandle.read(upToCount: 512 * 1024), !chunk.isEmpty {
                try outHandle.write(contentsOf: chunk)
            }
        }
    }

    // MARK: - Stage 2: Direct yt-dlp Execution & Stdout Progress Parser

    private static func executeDirectYTDLP(
        taskID: UUID,
        sourceURL: URL,
        format: YTDLPFormatOption,
        outputDirectory: URL,
        preferredFilename: String,
        sessionContext: BrowserSessionContext?,
        yield: @escaping @Sendable (YTDLPProgressEvent) -> Void
    ) async throws -> URL {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("PrismYTDLPDirect", isDirectory: true)
            .appendingPathComponent(taskID.uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let tempCookieURL = YTDLPExtractorService.writeEphemeralNetscapeCookies(from: sessionContext)
        defer {
            if let tempCookieURL { try? fm.removeItem(at: tempCookieURL) }
        }

        let safeStem = (preferredFilename as NSString).deletingPathExtension
        let outTemplate = tempDir.appendingPathComponent("\(safeStem).%(ext)s").path

        // Select single-file format so no external ffmpeg binary is needed by yt-dlp itself
        let singleFileSelector: String = format.isAudioOnly
            ? "bestaudio[ext=m4a]/bestaudio"
            : (format.resolutionHeight.map { "best[height<=\($0)][ext=mp4]/best[height<=\($0)]/best" } ?? "best[ext=mp4]/best")

        var args: [String] = [
            "--newline",
            "--progress",
            "--no-playlist",
            "--no-warnings",
            "--no-check-certificates",
            "-f", singleFileSelector,
            "-o", outTemplate,
        ]
        if let ua = sessionContext?.userAgent, !ua.isEmpty {
            args.append(contentsOf: ["--user-agent", ua])
        }
        if let ref = sessionContext?.pageReferer, !ref.isEmpty {
            args.append(contentsOf: ["--referer", ref])
        }
        if let tempCookieURL {
            args.append(contentsOf: ["--cookies", tempCookieURL.path])
        }
        args.append(sourceURL.absoluteString)

        let output = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<YTDLP.Output, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try YTDLP.shared.run(args, id: taskID.uuidString) { line, _ in
                        if let parsed = Self.parseProgressLine(line) {
                            let total = parsed.totalBytes ?? format.estimatedBytes
                            let downloaded = total.map { UInt64((Double($0) * parsed.fraction).rounded()) } ?? 0
                            yield(YTDLPProgressEvent(
                                taskID: taskID,
                                state: .downloading,
                                backend: .ytdlpDirect,
                                downloadedBytes: downloaded,
                                totalBytes: total,
                                isTotalBytesEstimated: parsed.totalBytes == nil,
                                speedBytesPerSecond: parsed.speedBytesPerSecond,
                                progressFraction: parsed.fraction
                            ))
                        }
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        if output.code == 130 {
            throw CancellationError()
        }
        guard output.code == 0 else {
            throw YTDLPExtractorError.extractionFailed(output.errorMessage ?? "yt-dlp failed (exit \(output.code))")
        }

        let produced = (try? fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        guard let downloadedFile = produced.max(by: {
            let s0 = (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let s1 = (try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return s0 < s1
        }) else {
            throw YTDLPExtractorError.extractionFailed("yt-dlp completed without producing an output file.")
        }

        let ext = downloadedFile.pathExtension.isEmpty ? format.containerExt : downloadedFile.pathExtension
        let desiredName = "\(safeStem).\(ext)"
        let finalDest = uniqueDestinationURL(in: outputDirectory, filename: desiredName)
        try fm.moveItem(at: downloadedFile, to: finalDest)
        return finalDest
    }

    /// Parses standard yt-dlp `--newline --progress` lines such as:
    /// `[download]  42.3% of   54.12MiB at    3.45MiB/s ETA 00:09`
    public static func parseProgressLine(_ line: String) -> YTDLPParsedProgressLine? {
        guard line.contains("[download]"), let pctRange = line.range(of: #"(\d+(?:\.\d+)?)%"#, options: .regularExpression) else {
            return nil
        }
        let pctStr = line[pctRange].dropLast()
        guard let pct = Double(pctStr) else { return nil }
        let fraction = min(max(pct / 100.0, 0.0), 1.0)

        var totalBytes: UInt64?
        if let ofRange = line.range(of: #"of\s+~?\s*([0-9.]+)\s*(KiB|MiB|GiB|KB|MB|GB|B)"#, options: .regularExpression) {
            totalBytes = parseByteUnitString(String(line[ofRange]))
        }

        var speedBps: UInt64 = 0
        if let atRange = line.range(of: #"at\s+([0-9.]+)\s*(KiB|MiB|GiB|KB|MB|GB|B)/s"#, options: .regularExpression) {
            speedBps = parseByteUnitString(String(line[atRange])) ?? 0
        }

        return YTDLPParsedProgressLine(fraction: fraction, totalBytes: totalBytes, speedBytesPerSecond: speedBps)
    }

    private static func parseByteUnitString(_ text: String) -> UInt64? {
        guard let numRange = text.range(of: #"[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression),
              let value = Double(text[numRange]) else {
            return nil
        }
        let lower = text.lowercased()
        let mult: Double
        if lower.contains("gib") { mult = 1024 * 1024 * 1024 }
        else if lower.contains("gb") { mult = 1_000_000_000 }
        else if lower.contains("mib") { mult = 1024 * 1024 }
        else if lower.contains("mb") { mult = 1_000_000 }
        else if lower.contains("kib") { mult = 1024 }
        else if lower.contains("kb") { mult = 1_000 }
        else { mult = 1 }
        return UInt64((value * mult).rounded())
    }

    private static func uniqueDestinationURL(in directory: URL, filename: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(filename)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let ext = candidate.pathExtension
        let stem = candidate.deletingPathExtension().lastPathComponent
        var i = 2
        while fm.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(stem) (\(i))" : "\(stem) (\(i)).\(ext)"
            candidate = directory.appendingPathComponent(next)
            i += 1
        }
        return candidate
    }
}

private final class ChunkProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private let ranges: [(Int, UInt64, UInt64)]
    private var downloadedByChunk: [UInt64]
    private let displayOffset: UInt64
    private let combinedTotal: UInt64
    private var lastEmit = Date.distantPast
    private var lastBytes: UInt64 = 0

    init(ranges: [(Int, UInt64, UInt64)], displayOffset: UInt64, combinedTotal: UInt64) {
        self.ranges = ranges
        self.downloadedByChunk = Array(repeating: 0, count: ranges.count)
        self.displayOffset = displayOffset
        self.combinedTotal = max(1, combinedTotal)
    }

    func record(chunkIndex: Int, addedBytes: UInt64, taskID: UUID, force: Bool = false) -> YTDLPProgressEvent? {
        lock.lock()
        defer { lock.unlock() }
        if chunkIndex < downloadedByChunk.count {
            downloadedByChunk[chunkIndex] += addedBytes
        }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastEmit)
        guard force || elapsed >= 0.166 else { return nil }

        let currentSum = downloadedByChunk.reduce(0, +)
        let deltaBytes = currentSum >= lastBytes ? currentSum - lastBytes : 0
        let speed = elapsed > 0.01 ? UInt64(Double(deltaBytes) / elapsed) : 0
        lastEmit = now
        lastBytes = currentSum

        let totalDownloaded = displayOffset + currentSum
        let fraction = min(0.97, Double(totalDownloaded) / Double(combinedTotal))

        let snapshots: [DownloadSegmentSnapshot] = ranges.enumerated().map { i, r in
            let len = r.2 - r.1 + 1
            let done = min(len, downloadedByChunk[i])
            return DownloadSegmentSnapshot(
                index: i,
                start: r.1,
                end: r.2,
                downloadedBytes: done
            )
        }

        return YTDLPProgressEvent(
            taskID: taskID,
            state: .downloading,
            backend: .ytdlpParallel,
            downloadedBytes: totalDownloaded,
            totalBytes: combinedTotal,
            isTotalBytesEstimated: false,
            speedBytesPerSecond: speed,
            progressFraction: fraction,
            segments: snapshots
        )
    }
}
