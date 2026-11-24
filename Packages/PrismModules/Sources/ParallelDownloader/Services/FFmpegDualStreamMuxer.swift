import Foundation
import Libavcodec
import Libavformat
import Libavutil

public enum FFmpegDualMuxError: LocalizedError, Sendable {
    case openInputFailed(String, Int32)
    case openOutputFailed(Int32)
    case streamCopyFailed(Int32)
    case writeHeaderFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .openInputFailed(let label, let code):
            return "FFmpeg could not open \(label) input (code \(code))."
        case .openOutputFailed(let code):
            return "FFmpeg could not create output MP4 container (code \(code))."
        case .streamCopyFailed(let code):
            return "FFmpeg stream copy setup failed (code \(code))."
        case .writeHeaderFailed(let code):
            return "FFmpeg could not write MP4 header (code \(code))."
        }
    }
}

/// Fast in-process C `Libavformat` / `Libavcodec` remuxer that merges locally downloaded
/// adaptive video + audio files (`-c copy`, `movflags=+faststart`) into a single `.mp4` at NVMe speed.
public enum FFmpegDualStreamMuxer {
    public static func remux(
        videoFileURL: URL,
        audioFileURL: URL?,
        outputURL: URL
    ) throws -> UInt64 {
        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try? fm.removeItem(at: outputURL)
        }

        var videoCtx: UnsafeMutablePointer<AVFormatContext>?
        let vOpen = avformat_open_input(&videoCtx, videoFileURL.path, nil, nil)
        guard vOpen >= 0, let vCtx = videoCtx else {
            throw FFmpegDualMuxError.openInputFailed("video", vOpen)
        }
        defer {
            var tmp: UnsafeMutablePointer<AVFormatContext>? = vCtx
            avformat_close_input(&tmp)
        }
        _ = avformat_find_stream_info(vCtx, nil)

        var audioCtx: UnsafeMutablePointer<AVFormatContext>?
        if let audioFileURL {
            let aOpen = avformat_open_input(&audioCtx, audioFileURL.path, nil, nil)
            guard aOpen >= 0, let aCtx = audioCtx else {
                throw FFmpegDualMuxError.openInputFailed("audio", aOpen)
            }
            _ = avformat_find_stream_info(aCtx, nil)
        }
        defer {
            var aTmp = audioCtx
            if aTmp != nil {
                avformat_close_input(&aTmp)
            }
        }

        var outCtx: UnsafeMutablePointer<AVFormatContext>?
        let allocRet = avformat_alloc_output_context2(&outCtx, nil, "mp4", outputURL.path)
        guard allocRet >= 0, let oCtx = outCtx else {
            throw FFmpegDualMuxError.openOutputFailed(allocRet)
        }
        defer {
            if let pb = oCtx.pointee.pb {
                var pbTmp: UnsafeMutablePointer<AVIOContext>? = pb
                avio_closep(&pbTmp)
                oCtx.pointee.pb = nil
            }
            avformat_free_context(oCtx)
        }

        var videoStreamMap: [Int32: Int32] = [:]
        var audioStreamMap: [Int32: Int32] = [:]

        // Copy video (and embedded audio if no separate audioFileURL)
        let vStreamCount = Int(vCtx.pointee.nb_streams)
        for i in 0..<vStreamCount {
            guard let inStream = vCtx.pointee.streams[i] else { continue }
            let codecType = inStream.pointee.codecpar.pointee.codec_type
            let shouldCopy = (codecType == AVMEDIA_TYPE_VIDEO) || (audioCtx == nil && codecType == AVMEDIA_TYPE_AUDIO)
            guard shouldCopy else { continue }

            guard let outStream = avformat_new_stream(oCtx, nil) else {
                throw FFmpegDualMuxError.streamCopyFailed(-1)
            }
            let copyRet = avcodec_parameters_copy(outStream.pointee.codecpar, inStream.pointee.codecpar)
            guard copyRet >= 0 else {
                throw FFmpegDualMuxError.streamCopyFailed(copyRet)
            }
            outStream.pointee.codecpar.pointee.codec_tag = 0
            outStream.pointee.time_base = inStream.pointee.time_base
            videoStreamMap[Int32(i)] = outStream.pointee.index
        }

        // Copy separate adaptive audio stream
        if let aCtx = audioCtx {
            let aStreamCount = Int(aCtx.pointee.nb_streams)
            for i in 0..<aStreamCount {
                guard let inStream = aCtx.pointee.streams[i] else { continue }
                guard inStream.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_AUDIO else { continue }

                guard let outStream = avformat_new_stream(oCtx, nil) else {
                    throw FFmpegDualMuxError.streamCopyFailed(-2)
                }
                let copyRet = avcodec_parameters_copy(outStream.pointee.codecpar, inStream.pointee.codecpar)
                guard copyRet >= 0 else {
                    throw FFmpegDualMuxError.streamCopyFailed(copyRet)
                }
                outStream.pointee.codecpar.pointee.codec_tag = 0
                outStream.pointee.time_base = inStream.pointee.time_base
                audioStreamMap[Int32(i)] = outStream.pointee.index
                break
            }
        }

        let openRet = avio_open(&oCtx.pointee.pb, outputURL.path, AVIO_FLAG_WRITE)
        guard openRet >= 0 else {
            throw FFmpegDualMuxError.openOutputFailed(openRet)
        }

        var muxOpts: OpaquePointer?
        av_dict_set(&muxOpts, "movflags", "+faststart", 0)
        let headerRet = avformat_write_header(oCtx, &muxOpts)
        av_dict_free(&muxOpts)
        guard headerRet >= 0 else {
            throw FFmpegDualMuxError.writeHeaderFailed(headerRet)
        }

        guard let pkt = av_packet_alloc() else {
            throw FFmpegDualMuxError.streamCopyFailed(-3)
        }
        defer {
            var pktTmp: UnsafeMutablePointer<AVPacket>? = pkt
            av_packet_free(&pktTmp)
        }

        func pumpInput(_ inCtx: UnsafeMutablePointer<AVFormatContext>, streamMap: [Int32: Int32]) {
            while av_read_frame(inCtx, pkt) >= 0 {
                defer { av_packet_unref(pkt) }
                guard let outIdx = streamMap[pkt.pointee.stream_index],
                      let inStream = inCtx.pointee.streams[Int(pkt.pointee.stream_index)],
                      let outStream = oCtx.pointee.streams[Int(outIdx)] else {
                    continue
                }
                pkt.pointee.stream_index = outIdx
                av_packet_rescale_ts(pkt, inStream.pointee.time_base, outStream.pointee.time_base)
                pkt.pointee.pos = -1
                _ = av_interleaved_write_frame(oCtx, pkt)
            }
        }

        pumpInput(vCtx, streamMap: videoStreamMap)
        if let aCtx = audioCtx {
            pumpInput(aCtx, streamMap: audioStreamMap)
        }

        _ = av_write_trailer(oCtx)

        let attrs = try fm.attributesOfItem(atPath: outputURL.path)
        return (attrs[.size] as? NSNumber)?.uint64Value ?? 0
    }
}
