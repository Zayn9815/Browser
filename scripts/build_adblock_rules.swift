#!/usr/bin/env swift
import CryptoKit
import Foundation

// MARK: - CLI Options

private struct BuildOptions {
    var outputDir: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("App/Resources/AdBlockShards", isDirectory: true)
    var maxRulesPerShard: Int = 125_000
}

private func parseOptions() -> BuildOptions {
    var opts = BuildOptions()
    var i = 1
    let args = CommandLine.arguments
    while i < args.count {
        switch args[i] {
        case "--output-dir" where i + 1 < args.count:
            opts.outputDir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
            i += 2
        case "--max-rules-per-shard" where i + 1 < args.count:
            if let value = Int(args[i + 1]), value > 0, value <= 150_000 {
                opts.maxRulesPerShard = value
            }
            i += 2
        default:
            i += 1
        }
    }
    return opts
}

// MARK: - WebKit Content Blocker JSON Models

private struct ContentBlockerRule: Encodable {
    struct Trigger: Encodable {
        let urlFilter: String
        let urlFilterIsCaseSensitive: Bool?
        let resourceType: [String]?
        let loadType: [String]?
        let ifDomain: [String]?
        let unlessDomain: [String]?

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case urlFilterIsCaseSensitive = "url-filter-is-case-sensitive"
            case resourceType = "resource-type"
            case loadType = "load-type"
            case ifDomain = "if-domain"
            case unlessDomain = "unless-domain"
        }
    }

    struct Action: Encodable {
        let type: String
        let selector: String?
    }

    let trigger: Trigger
    let action: Action
}

private struct ShardManifest: Encodable {
    struct ShardDescriptor: Encodable {
        let identifier: String
        let sourceList: String
        let filename: String
        let ruleCount: Int
        let sha256: String
    }

    let bundleVersion: String
    let generatedAtISO8601: String
    let maxRulesPerShard: Int
    let totalRuleCount: Int
    let shards: [ShardDescriptor]
}

// MARK: - ABP Filter -> Strict ASCII WebKit DFA Rule Converter

private func isStrictASCII(_ text: String) -> Bool {
    text.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value <= 0x7E }
}

private func escapeRegexLiteral(_ raw: String) -> String {
    let meta = Set<Character>([".", "+", "?", "(", ")", "[", "]", "{", "}", "\\", "$", "^", "|"])
    var out = ""
    out.reserveCapacity(raw.count + 8)
    for ch in raw {
        if meta.contains(ch) {
            out.append("\\")
        }
        out.append(ch)
    }
    return out
}

private func normalizeDomainToken(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty, isStrictASCII(trimmed), !trimmed.contains("*"), !trimmed.contains("/") else {
        return nil
    }
    return "*\(trimmed)"
}

private func isValidWebKitRegex(_ pattern: String) -> Bool {
    guard !pattern.isEmpty, pattern.count <= 256, isStrictASCII(pattern) else { return false }
    // Reject PCRE extensions unsupported by WebKit DFA engine (lookarounds, backrefs, non-greedy)
    if pattern.contains("(?") || pattern.contains("\\1") || pattern.contains("\\2") || pattern.contains("*?") || pattern.contains("+?") {
        return false
    }
    // Validate syntax via Foundation NSRegularExpression
    return (try? NSRegularExpression(pattern: pattern, options: [])) != nil
}

private func convertABPLineToRule(_ rawLine: String) -> ContentBlockerRule? {
    let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
    if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[Adblock") {
        return nil
    }

    // Cosmetic element hiding rules (##selector or domain1,domain2##selector)
    if line.contains("##"), !line.contains("#@#"), !line.contains("#?#"), !line.contains(":has("), !line.contains(":style("), !line.contains(":-abp-") {
        let parts = line.components(separatedBy: "##")
        guard parts.count == 2 else { return nil }
        let domainPart = parts[0].trimmingCharacters(in: .whitespaces)
        let selector = parts[1].trimmingCharacters(in: .whitespaces)
        guard !selector.isEmpty, selector.count <= 256, isStrictASCII(selector) else { return nil }

        var ifDomains: [String] = []
        var unlessDomains: [String] = []
        if !domainPart.isEmpty {
            for token in domainPart.split(separator: ",") {
                let s = String(token)
                if s.hasPrefix("~") {
                    if let d = normalizeDomainToken(String(s.dropFirst())) { unlessDomains.append(d) }
                } else {
                    if let d = normalizeDomainToken(s) { ifDomains.append(d) }
                }
            }
            // WebKit forbids setting both if-domain and unless-domain on one rule
            if !ifDomains.isEmpty && !unlessDomains.isEmpty {
                unlessDomains.removeAll()
            }
            if ifDomains.isEmpty && unlessDomains.isEmpty {
                return nil
            }
        }

        return ContentBlockerRule(
            trigger: .init(
                urlFilter: ".*",
                urlFilterIsCaseSensitive: nil,
                resourceType: nil,
                loadType: nil,
                ifDomain: ifDomains.isEmpty ? nil : ifDomains,
                unlessDomain: unlessDomains.isEmpty ? nil : unlessDomains
            ),
            action: .init(type: "css-display-none", selector: selector)
        )
    }

    // Skip unsupported extended cosmetic/scriptlet rules
    if line.contains("#@#") || line.contains("#?#") || line.contains("#$#") || line.contains("##+") {
        return nil
    }

    var working = line
    let isException: Bool
    if working.hasPrefix("@@") {
        isException = true
        working = String(working.dropFirst(2))
    } else {
        isException = false
    }

    // Split optional $options
    var patternPart = working
    var optionsPart = ""
    if let dollarIdx = working.lastIndex(of: "$"), !working.hasPrefix("/") {
        patternPart = String(working[..<dollarIdx])
        optionsPart = String(working[working.index(after: dollarIdx)...])
    }

    // Skip raw regex filters (/.../) to avoid WebKit DFA compilation blowups
    if patternPart.hasPrefix("/") && patternPart.hasSuffix("/") {
        return nil
    }
    guard !patternPart.isEmpty, isStrictASCII(patternPart) else { return nil }

    var resourceTypes: Set<String> = []
    var loadTypes: [String]? = nil
    var ifDomains: [String] = []
    var unlessDomains: [String] = []
    var caseSensitive: Bool? = nil

    if !optionsPart.isEmpty {
        for rawOpt in optionsPart.split(separator: ",") {
            let opt = String(rawOpt).trimmingCharacters(in: .whitespaces).lowercased()
            switch opt {
            case "third-party", "3p":
                loadTypes = ["third-party"]
            case "~third-party", "first-party", "1p":
                loadTypes = ["first-party"]
            case "script":
                resourceTypes.insert("script")
            case "image":
                resourceTypes.insert("image")
            case "stylesheet":
                resourceTypes.insert("style-sheet")
            case "xmlhttprequest", "xhr", "fetch":
                resourceTypes.insert("raw")
            case "subdocument":
                resourceTypes.insert("document")
            case "font":
                resourceTypes.insert("font")
            case "media":
                resourceTypes.insert("media")
            case "popup":
                resourceTypes.insert("popup")
            case "match-case":
                caseSensitive = true
            case "document", "elemhide", "generichide", "genericblock", "important", "badfilter", "csp", "redirect", "removeparam":
                // Skip rules relying on non-WebKit modifiers
                if opt == "badfilter" || opt == "csp" || opt == "redirect" || opt == "removeparam" {
                    return nil
                }
            default:
                if opt.hasPrefix("domain=") {
                    let domList = opt.dropFirst("domain=".count)
                    for token in domList.split(separator: "|") {
                        let s = String(token)
                        if s.hasPrefix("~") {
                            if let d = normalizeDomainToken(String(s.dropFirst())) { unlessDomains.append(d) }
                        } else {
                            if let d = normalizeDomainToken(s) { ifDomains.append(d) }
                        }
                    }
                }
            }
        }
    }

    if !ifDomains.isEmpty && !unlessDomains.isEmpty {
        unlessDomains.removeAll()
    }

    // Translate ABP wildcards/anchors to WebKit URL regex
    var regex = ""
    var body = patternPart
    var anchorStartDomain = false
    var anchorStartExact = false
    var anchorEnd = false

    if body.hasPrefix("||") {
        anchorStartDomain = true
        body = String(body.dropFirst(2))
    } else if body.hasPrefix("|") {
        anchorStartExact = true
        body = String(body.dropFirst(1))
    }

    if body.hasSuffix("|") {
        anchorEnd = true
        body = String(body.dropLast(1))
    }

    guard !body.isEmpty else { return nil }

    if anchorStartDomain {
        regex += "^https?://+([^:/]+\\.)?"
    } else if anchorStartExact {
        regex += "^"
    }

    // Convert * -> .* and ^ -> separator character class
    let segments = body.split(separator: "*", omittingEmptySubsequences: false)
    var translatedSegments: [String] = []
    for seg in segments {
        let caretParts = seg.split(separator: "^", omittingEmptySubsequences: false)
        let escapedCarets = caretParts.map { escapeRegexLiteral(String($0)) }
        translatedSegments.append(escapedCarets.joined(separator: "[/:?&=#]"))
    }
    regex += translatedSegments.joined(separator: ".*")

    if anchorEnd {
        regex += "$"
    }

    guard isValidWebKitRegex(regex) else { return nil }

    let sortedTypes = resourceTypes.isEmpty ? nil : resourceTypes.sorted()
    return ContentBlockerRule(
        trigger: .init(
            urlFilter: regex,
            urlFilterIsCaseSensitive: caseSensitive,
            resourceType: sortedTypes,
            loadType: loadTypes,
            ifDomain: ifDomains.isEmpty ? nil : ifDomains,
            unlessDomain: unlessDomains.isEmpty ? nil : unlessDomains
        ),
        action: .init(type: isException ? "ignore-previous-rules" : "block", selector: nil)
    )
}

private final class FetchResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _data: Data?
    private var _error: Error?

    func store(data: Data?, error: Error?) {
        lock.lock()
        _data = data
        _error = error
        lock.unlock()
    }

    func snapshot() -> (Data?, Error?) {
        lock.lock()
        defer { lock.unlock() }
        return (_data, _error)
    }
}

private func downloadText(from urlString: String) throws -> String {
    guard let url = URL(string: urlString) else {
        throw NSError(domain: "AdBlockBuilder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL \(urlString)"])
    }
    let semaphore = DispatchSemaphore(value: 0)
    let box = FetchResultBox()

    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
    request.setValue("PrismDM-AdBlockBuilder/1.0", forHTTPHeaderField: "User-Agent")

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        if let error {
            box.store(data: nil, error: error)
            return
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let statusError = NSError(
                domain: "AdBlockBuilder",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) fetching \(urlString)"]
            )
            box.store(data: nil, error: statusError)
            return
        }
        box.store(data: data, error: nil)
    }
    task.resume()
    semaphore.wait()

    let (fetchedData, fetchError) = box.snapshot()
    if let fetchError { throw fetchError }
    guard let data = fetchedData, let text = String(data: data, encoding: .utf8) else {
        throw NSError(domain: "AdBlockBuilder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Empty or non-UTF8 response from \(urlString)"])
    }
    return text
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

// MARK: - Main Execution

do {
    let options = parseOptions()
    let fm = FileManager.default
    try fm.createDirectory(at: options.outputDir, withIntermediateDirectories: true)

    // Remove previously generated JSON shards before writing fresh ones
    if let existing = try? fm.contentsOfDirectory(at: options.outputDir, includingPropertiesForKeys: nil) {
        for file in existing where file.pathExtension == "json" {
            try fm.removeItem(at: file)
        }
    }

    let sources: [(name: String, url: String)] = [
        ("easylist", "https://easylist.to/easylist/easylist.txt"),
        ("easyprivacy", "https://easylist.to/easylist/easyprivacy.txt")
    ]

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]

    var descriptors: [ShardManifest.ShardDescriptor] = []
    var totalRuleCount = 0
    var combinedHashInput = Data()

    for source in sources {
        print("[adblock-builder] Fetching \(source.name) from \(source.url)...")
        let rawText = try downloadText(from: source.url)

        var blockRules: [ContentBlockerRule] = []
        var exceptionRules: [ContentBlockerRule] = []
        var seenSignatures = Set<String>()

        for line in rawText.split(whereSeparator: \.isNewline) {
            guard let rule = convertABPLineToRule(String(line)) else { continue }
            let sig = "\(rule.action.type)|\(rule.action.selector ?? "")|\(rule.trigger.urlFilter)|\(rule.trigger.ifDomain?.joined(separator: ",") ?? "")"
            guard seenSignatures.insert(sig).inserted else { continue }
            if rule.action.type == "ignore-previous-rules" {
                exceptionRules.append(rule)
            } else {
                blockRules.append(rule)
            }
        }

        // Order block/cosmetic rules first, then ignore-previous-rules exceptions
        let orderedRules = blockRules + exceptionRules
        guard !orderedRules.isEmpty else {
            throw NSError(domain: "AdBlockBuilder", code: 3, userInfo: [NSLocalizedDescriptionKey: "Converted 0 rules for \(source.name)"])
        }

        let shardCap = options.maxRulesPerShard
        var offset = 0
        var shardIndex = 0
        while offset < orderedRules.count {
            let end = min(offset + shardCap, orderedRules.count)
            let slice = Array(orderedRules[offset..<end])
            let jsonData = try encoder.encode(slice)
            let digest = sha256Hex(jsonData)
            let shortHash = String(digest.prefix(12))
            let filename = "\(source.name)_shard_\(shardIndex).json"
            let identifier = "\(source.name)_shard_\(shardIndex)_\(shortHash)"

            try jsonData.write(to: options.outputDir.appendingPathComponent(filename), options: .atomic)
            descriptors.append(.init(
                identifier: identifier,
                sourceList: source.name,
                filename: filename,
                ruleCount: slice.count,
                sha256: digest
            ))
            combinedHashInput.append(Data(digest.utf8))
            totalRuleCount += slice.count
            print("[adblock-builder] Wrote \(filename): \(slice.count) rules (\(jsonData.count / 1024) KB, sha256=\(shortHash))")

            offset = end
            shardIndex += 1
        }
    }

    let formatter = ISO8601DateFormatter()
    let bundleVersion = String(sha256Hex(combinedHashInput).prefix(16))
    let manifest = ShardManifest(
        bundleVersion: bundleVersion,
        generatedAtISO8601: formatter.string(from: Date()),
        maxRulesPerShard: options.maxRulesPerShard,
        totalRuleCount: totalRuleCount,
        shards: descriptors
    )

    let prettyEncoder = JSONEncoder()
    prettyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let manifestData = try prettyEncoder.encode(manifest)
    let manifestURL = options.outputDir.appendingPathComponent("manifest.json")
    try manifestData.write(to: manifestURL, options: .atomic)
    print("[adblock-builder] Completed \(descriptors.count) shards (\(totalRuleCount) total rules, version=\(bundleVersion)) -> \(manifestURL.path)")
} catch {
    fputs("[adblock-builder] error: \(error)\n", stderr)
    exit(1)
}
