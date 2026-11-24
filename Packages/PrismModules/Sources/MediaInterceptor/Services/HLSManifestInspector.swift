import Foundation
import ParallelDownloader
import PrismPlayer

public enum HLSManifestError: LocalizedError, Sendable {
    case httpError(Int)
    case emptyManifest

    public var errorDescription: String? {
        switch self {
        case .httpError(let status):
            return "Manifest server returned HTTP \(status)."
        case .emptyManifest:
            return "HLS playlist contained no readable text."
        }
    }
}

public struct HLSManifestInspector: Sendable {
    public init() {}

    /// Fetches an `.m3u8` master playlist with full browser session headers and parses sorted variants.
    public func fetchVariants(
        from masterURL: URL,
        sessionContext: BrowserSessionContext
    ) async throws -> [HLSStreamVariant] {
        var request = URLRequest(url: masterURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        for (header, value) in sessionContext.httpHeaderDictionary(for: masterURL) {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HLSManifestError.httpError(http.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw HLSManifestError.emptyManifest
        }
        return Self.parseMasterPlaylist(text, baseURL: masterURL)
    }

    /// Parses `#EXT-X-STREAM-INF` entries from an HLS master playlist into sorted `HLSStreamVariant` items.
    public static func parseMasterPlaylist(_ playlistText: String, baseURL: URL) -> [HLSStreamVariant] {
        let lines = playlistText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var variants: [HLSStreamVariant] = []
        var seenURLs = Set<String>()
        var pendingAttributes: [String: String]?

        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                let rawAttrs = String(line.dropFirst("#EXT-X-STREAM-INF:".count))
                pendingAttributes = parseAttributeList(rawAttrs)
            } else if line.hasPrefix("#") {
                continue
            } else if let attrs = pendingAttributes {
                pendingAttributes = nil
                guard let resolvedURL = URL(string: line, relativeTo: baseURL)?.absoluteURL else { continue }
                guard seenURLs.insert(resolvedURL.absoluteString).inserted else { continue }

                let bandwidth = Int(attrs["BANDWIDTH"] ?? "") ?? Int(attrs["AVERAGE-BANDWIDTH"] ?? "") ?? 0
                var width: Int?
                var height: Int?
                if let res = attrs["RESOLUTION"] {
                    let dims = res.lowercased().split(separator: "x")
                    if dims.count == 2, let w = Int(dims[0]), let h = Int(dims[1]) {
                        width = w
                        height = h
                    }
                }
                let frameRate = attrs["FRAME-RATE"].flatMap(Double.init)
                let codecs = attrs["CODECS"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))

                variants.append(
                    HLSStreamVariant(
                        url: resolvedURL,
                        width: width,
                        height: height,
                        bandwidthBitsPerSec: bandwidth,
                        frameRate: frameRate,
                        codecs: codecs
                    )
                )
            }
        }

        return variants.sorted { lhs, rhs in
            let lHeight = lhs.height ?? 0
            let rHeight = rhs.height ?? 0
            if lHeight != rHeight {
                return lHeight > rHeight
            }
            return lhs.bandwidthBitsPerSec > rhs.bandwidthBitsPerSec
        }
    }

    private static func parseAttributeList(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        var key = ""
        var value = ""
        var readingKey = true
        var inQuotes = false

        func commit() {
            let trimmedKey = key.trimmingCharacters(in: .whitespaces).uppercased()
            let trimmedVal = value.trimmingCharacters(in: .whitespaces)
            if !trimmedKey.isEmpty {
                result[trimmedKey] = trimmedVal
            }
            key = ""
            value = ""
            readingKey = true
        }

        for ch in raw {
            if ch == "\"" {
                inQuotes.toggle()
                value.append(ch)
            } else if ch == "=" && readingKey && !inQuotes {
                readingKey = false
            } else if ch == "," && !inQuotes {
                commit()
            } else if readingKey {
                key.append(ch)
            } else {
                value.append(ch)
            }
        }
        commit()
        return result
    }
}
