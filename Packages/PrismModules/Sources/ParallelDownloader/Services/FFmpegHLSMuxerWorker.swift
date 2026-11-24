import Foundation
import Libavcodec
import Libavformat
import Libavutil
import SDMCore

public struct HLSMuxProgressEvent: Sendable, Equatable {
    public let taskID: UUID
    public let state: DownloadState
    public let downloadedBytes: UInt64
    public let speedBytesPerSecond: UInt64
    public let progressFraction: Double?
    public let outputURL: URL?
    public let errorMessage: String?

    public init(
        taskID: UUID,
        state: DownloadState,
        downloadedBytes: UInt64,
        speedBytesPerSecond: UInt64,
        progressFraction: Double?,
        outputURL: URL? = nil,
        errorMessage: String? = nil
    ) {
        self.taskID = taskID
        self.state = state
        self.downloadedBytes = downloadedBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.progressFraction = progressFraction
        self.outputURL = outputURL
        self.errorMessage = errorMessage
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

/// Thread-safe, in-process C `Libavformat` / `Libavcodec` HLS/DASH stream-copy remuxer (`-c copy -bsf:a aac_adtstoasc -movflags +faststart`).
public actor FFmpegHLSMuxerWorker {
    private var interruptFlags: [UUID: MuxInterruptFlag] = [:]

    public init() {
        avformat_network_init()
    }

    public func cancelTask(_ id: UUID) {
        interruptFlags[id]?.cancel()
    }

    /// Streams an HTTPS `.m3u8` (or unencrypted `.mpd`) manifest directly into an MP4 file at `outputURL`
    /// without re-encoding, emitting throttled progress events via `AsyncStream`.
    public func startRemux(
        taskID: UUID,
        sourceURL: URL,
        outputURL: URL,
        crlfHeaders: String
    ) -> AsyncStream<HLSMuxProgressEvent> {
        let cancelFlag = MuxInterruptFlag()
        interruptFlags[taskID] = cancelFlag
        let worker = self

        return AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
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
                        speedBytesPerSecond: 0,
                        progressFraction: nil
                    )
                )

                do {
                    let totalBytes = try Self.executeRemuxBlocking(
                        taskID: taskID,
                        sourceURLString: sourceURL.absoluteString,
                        outputPath: outputURL.path(percentEncoded: false),
                        crlfHeaders: crlfHeaders,
                        cancelFlag: cancelFlag,
                        onProgress: { bytes, speed, fraction in
                            continuation.yield(
                                HLSMuxProgressEvent(
                                    taskID: taskID,
                                    state: .downloading,
                                    downloadedBytes: bytes,
                                    speedBytesPerSecond: speed,
                                    progressFraction: fraction
                                )
                            )
                        }
                    )

                    if cancelFlag.isInterrupted() {
                        try? FileManager.default.removeItem(at: outputURL)
                        continuation.yield(
                            HLSMuxProgressEvent(
                                taskID: taskID,
                                state: .cancelled,
                                downloadedBytes: totalBytes,
                                speedBytesPerSecond: 0,
                                progressFraction: nil
                            )
                        )
                    } else {
                        continuation.yield(
                            HLSMuxProgressEvent(
                                taskID: taskID,
                                state: .completed,
                                downloadedBytes: totalBytes,
                                speedBytesPerSecond: 0,
                                progressFraction: 1.0,
                                outputURL: outputURL
                            )
                        )
                    }
                } catch {
                    try? FileManager.default.removeItem(at: outputURL)
                    let finalState: DownloadState = cancelFlag.isInterrupted() ? .cancelled : .failed
                    continuation.yield(
                        HLSMuxProgressEvent(
                            taskID: taskID,
                            state: finalState,
                            downloadedBytes: 0,
                            speedBytesPerSecond: 0,
                            progressFraction: nil,
                            errorMessage: finalState == .cancelled ? nil : error.localizedDescription
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

    // MARK: - In-Process Libavformat / Libavcodec Stream-Copy Remuxer

    private static func executeRemuxBlocking(
        taskID: UUID,
        sourceURLString: String,
        outputPath: String,
        crlfHeaders: String,
        cancelFlag: MuxInterruptFlag,
        onProgress: (_ writtenBytes: UInt64, _ speedBytesPerSec: UInt64, _ fraction: Double?) -> Void
    ) throws -> UInt64 {
        var inCtx: UnsafeMutablePointer<AVFormatContext>? = avformat_alloc_context()
        guard let allocatedIn = inCtx else {
            throw NSError(domain: "PrismFFmpegMuxer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate AVFormatContext."])
        }

        // Attach AVIOInterruptCB BEFORE avformat_open_input so network handshakes cancel immediately
        allocatedIn.pointee.interrupt_callback = AVIOInterruptCB(
            callback: prismAVIOInterruptCallback,
            opaque: Unmanaged.passUnretained(cancelFlag).toOpaque()
        )

        var inOpts: OpaquePointer?
        defer {
            if inOpts != nil { av_dict_free(&inOpts) }
            if inCtx != nil { avformat_close_input(&inCtx) }
        }

        if !crlfHeaders.isEmpty {
            av_dict_set(&inOpts, "headers", crlfHeaders, 0)
        }
        av_dict_set(&inOpts, "reconnect", "1", 0)
        av_dict_set(&inOpts, "reconnect_streamed", "1", 0)
        av_dict_set(&inOpts, "reconnect_delay_max", "5", 0)
        av_dict_set(&inOpts, "rw_timeout", "15000000", 0)
        av_dict_set(&inOpts, "protocol_whitelist", "file,http,https,tcp,tls,crypto,hls,concat,data", 0)

        let openErr = avformat_open_input(&inCtx, sourceURLString, nil, &inOpts)
        guard openErr >= 0, let input = inCtx else {
            throw NSError(domain: "PrismFFmpegMuxer", code: Int(openErr), userInfo: [
                NSLocalizedDescriptionKey: "Failed to open HLS stream: \(ffmpegErrorDescription(openErr))"
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

            // Apply aac_adtstoasc bitstream filter on AAC audio streams for clean MP4 playback
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

            // Emit progress at most ~6 Hz (every 166 ms) inside the C worker to keep MainActor cool
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
