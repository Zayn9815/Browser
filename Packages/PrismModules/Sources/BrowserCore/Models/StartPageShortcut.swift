import Foundation
import Observation
import UIKit

public struct StartPageShortcut: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var urlString: String
    public var brandHex: UInt32

    public init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        brandHex: UInt32 = 0xFF2D55
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.brandHex = brandHex
    }

    public var url: URL? {
        URL(string: urlString)
    }

    public var host: String {
        url?.host?.lowercased() ?? urlString.lowercased()
    }

    public var monogram: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "W"
    }

    public static let defaultShortcuts: [StartPageShortcut] = [
        StartPageShortcut(title: "YouTube", urlString: "https://m.youtube.com", brandHex: 0xFF0033),
        StartPageShortcut(title: "Facebook", urlString: "https://m.facebook.com", brandHex: 0x1877F2),
        StartPageShortcut(title: "Google", urlString: "https://www.google.com", brandHex: 0x4285F4),
        StartPageShortcut(title: "X", urlString: "https://x.com", brandHex: 0x22242A),
        StartPageShortcut(title: "Reddit", urlString: "https://www.reddit.com", brandHex: 0xFF4500),
        StartPageShortcut(title: "Wikipedia", urlString: "https://en.m.wikipedia.org", brandHex: 0x63666A),
        StartPageShortcut(title: "GitHub", urlString: "https://github.com", brandHex: 0x2B3137),
        StartPageShortcut(title: "Instagram", urlString: "https://www.instagram.com", brandHex: 0xE1306C),
    ]
}

@Observable
@MainActor
public final class StartPageShortcutStore {
    public var shortcuts: [StartPageShortcut]
    public private(set) var cachedFaviconsByHost: [String: UIImage] = [:]

    private let storageKey = "prismdm.v1.startPageShortcuts"
    private let faviconCacheDir: URL
    private var inFlightHosts: Set<String> = []

    public init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.faviconCacheDir = caches.appendingPathComponent("Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: faviconCacheDir, withIntermediateDirectories: true)

        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([StartPageShortcut].self, from: data) {
            self.shortcuts = decoded
        } else {
            self.shortcuts = StartPageShortcut.defaultShortcuts
        }
        loadCachedFaviconsFromDisk()
    }

    public func addShortcut(title: String, rawURL: String) {
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        let normalizedURLString: String
        if trimmedURL.lowercased().hasPrefix("http://") || trimmedURL.lowercased().hasPrefix("https://") {
            normalizedURLString = trimmedURL
        } else {
            normalizedURLString = "https://\(trimmedURL)"
        }
        guard let parsed = URL(string: normalizedURLString), let host = parsed.host, !host.isEmpty else {
            return
        }
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanedTitle.isEmpty ? host.replacingOccurrences(of: "www.", with: "") : cleanedTitle
        let palettePool: [UInt32] = [0xFF2D55, 0x0A84FF, 0x32D74B, 0xFF9F0A, 0xAF52DE, 0x00C7BE]
        let colorHex = palettePool[abs(host.hashValue) % palettePool.count]

        let shortcut = StartPageShortcut(title: finalTitle, urlString: parsed.absoluteString, brandHex: colorHex)
        shortcuts.append(shortcut)
        persist()
        fetchFaviconIfNeeded(for: shortcut)
    }

    public func updateShortcut(id: UUID, title: String, rawURL: String) {
        guard let idx = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedURLString = (trimmedURL.lowercased().hasPrefix("http://") || trimmedURL.lowercased().hasPrefix("https://"))
            ? trimmedURL
            : "https://\(trimmedURL)"
        guard let parsed = URL(string: normalizedURLString), parsed.host != nil else { return }
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        shortcuts[idx].title = cleanedTitle.isEmpty ? (parsed.host ?? "Site") : cleanedTitle
        shortcuts[idx].urlString = parsed.absoluteString
        persist()
        fetchFaviconIfNeeded(for: shortcuts[idx])
    }

    public func removeShortcut(id: UUID) {
        shortcuts.removeAll { $0.id == id }
        persist()
    }

    public func moveShortcut(id: UUID, by offset: Int) {
        guard let idx = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(0, idx + offset), shortcuts.count - 1)
        guard target != idx else { return }
        let item = shortcuts.remove(at: idx)
        shortcuts.insert(item, at: target)
        persist()
    }

    public func resetToDefaults() {
        shortcuts = StartPageShortcut.defaultShortcuts
        persist()
    }

    public func fetchFaviconIfNeeded(for shortcut: StartPageShortcut) {
        let host = shortcut.host
        guard !host.isEmpty, cachedFaviconsByHost[host] == nil, !inFlightHosts.contains(host) else {
            return
        }
        inFlightHosts.insert(host)
        let cacheURL = faviconFileURL(for: host)
        let targetFaviconURL = URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(host)")

        Task { @MainActor [weak self] in
            defer { self?.inFlightHosts.remove(host) }
            guard let self, let url = targetFaviconURL else { return }
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
            request.setValue(BrowserEngineDefaults.mobileUserAgent, forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let image = UIImage(data: data),
                  image.size.width >= 16 else {
                return
            }
            if let png = image.pngData() {
                try? png.write(to: cacheURL, options: .atomic)
            }
            self.cachedFaviconsByHost[host] = image
        }
    }

    private func loadCachedFaviconsFromDisk() {
        for shortcut in shortcuts {
            let host = shortcut.host
            let fileURL = faviconFileURL(for: host)
            if let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
                cachedFaviconsByHost[host] = img
            }
        }
    }

    private func faviconFileURL(for host: String) -> URL {
        let safe = host.replacingOccurrences(of: "[^a-z0-9.-]", with: "_", options: .regularExpression)
        return faviconCacheDir.appendingPathComponent("\(safe).png")
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
