import Foundation
import Observation
import PrismCore
import Translation
import WebKit

public struct TranslationTargetLanguage: Identifiable, Hashable, Sendable {
    public let code: String
    public let displayName: String

    public var id: String { code }
    public var localeLanguage: Locale.Language { Locale.Language(identifier: code) }

    public static let supported: [TranslationTargetLanguage] = [
        TranslationTargetLanguage(code: "en", displayName: "English"),
        TranslationTargetLanguage(code: "es", displayName: "Spanish"),
        TranslationTargetLanguage(code: "fr", displayName: "French"),
        TranslationTargetLanguage(code: "de", displayName: "German"),
        TranslationTargetLanguage(code: "ar", displayName: "Arabic"),
        TranslationTargetLanguage(code: "hi", displayName: "Hindi"),
        TranslationTargetLanguage(code: "ur", displayName: "Urdu"),
        TranslationTargetLanguage(code: "ja", displayName: "Japanese"),
        TranslationTargetLanguage(code: "ko", displayName: "Korean"),
        TranslationTargetLanguage(code: "zh-Hans", displayName: "Chinese (Simplified)"),
        TranslationTargetLanguage(code: "pt", displayName: "Portuguese"),
        TranslationTargetLanguage(code: "ru", displayName: "Russian"),
        TranslationTargetLanguage(code: "tr", displayName: "Turkish"),
    ]
}

private struct DOMTextSegment: Codable, Sendable {
    let id: String
    let text: String
}

/// Manages Apple's native on-device `Translation` framework (`TranslationSession`) in-place DOM translation
/// with instant revert-to-original and one-tap Google Translate web fallback.
@Observable
@MainActor
public final class PageTranslationService {
    public var isBannerVisible: Bool = false
    public var isTranslating: Bool = false
    public var isShowingTranslated: Bool = false
    public var selectedTarget: TranslationTargetLanguage = TranslationTargetLanguage.supported[0]
    public var statusMessage: String?
    public var showGoogleFallbackOffer: Bool = false
    public var configuration: TranslationSession.Configuration?

    private weak var targetWebView: WKWebView?

    public init() {}

    public func beginTranslation(in webView: WKWebView?, target: TranslationTargetLanguage? = nil) {
        guard let webView, webView.url != nil else {
            statusMessage = "Open a webpage first to translate."
            return
        }
        if let target {
            selectedTarget = target
        }
        targetWebView = webView
        isBannerVisible = true
        isTranslating = true
        showGoogleFallbackOffer = false
        statusMessage = "Translating to \(selectedTarget.displayName)…"

        if configuration == nil {
            configuration = TranslationSession.Configuration(
                source: nil,
                target: selectedTarget.localeLanguage
            )
        } else {
            configuration?.target = selectedTarget.localeLanguage
            configuration?.invalidate()
        }
    }

    public func runTranslationSession(_ session: TranslationSession) async {
        guard let webView = targetWebView else {
            isTranslating = false
            return
        }

        do {
            let rawJSON: Any? = try await webView.evaluateJavaScript(
                "typeof window.__prismCollectTranslatableSegments === 'function' ? window.__prismCollectTranslatableSegments(240) : '[]'",
                in: nil,
                in: .defaultClient
            )
            guard let jsonString = rawJSON as? String,
                  let data = jsonString.data(using: .utf8),
                  let segments = try? JSONDecoder().decode([DOMTextSegment].self, from: data),
                  !segments.isEmpty else {
                isTranslating = false
                statusMessage = "No translatable text found on this page."
                return
            }

            let requests = segments.map {
                TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id)
            }
            let responses = try await session.translations(from: requests)
            let translatedSegments = responses.compactMap { resp -> DOMTextSegment? in
                guard let id = resp.clientIdentifier else { return nil }
                return DOMTextSegment(id: id, text: resp.targetText)
            }

            let encodedData = try JSONEncoder().encode(translatedSegments)
            guard let encodedJSON = String(data: encodedData, encoding: .utf8) else {
                isTranslating = false
                return
            }

            let jsPayloadData = try JSONSerialization.data(withJSONObject: [encodedJSON], options: [])
            let jsArrayLiteral = String(data: jsPayloadData, encoding: .utf8) ?? "[]"
            _ = try await webView.evaluateJavaScript(
                "if (typeof window.__prismApplyTranslatedSegments === 'function') { window.__prismApplyTranslatedSegments((\(jsArrayLiteral))[0]); }",
                in: nil,
                in: .defaultClient
            )

            isTranslating = false
            isShowingTranslated = true
            showGoogleFallbackOffer = false
            statusMessage = "Translated to \(selectedTarget.displayName)"
            PrismLogCenter.record(.info, category: .browser, "Translated \(translatedSegments.count) DOM segments to \(selectedTarget.code).")
        } catch {
            isTranslating = false
            showGoogleFallbackOffer = true
            statusMessage = "On-device pack unavailable. Tap Google Translate fallback."
            PrismLogCenter.record(.warning, category: .browser, "On-device translation failed: \(error.localizedDescription)")
        }
    }

    public func restoreOriginal() {
        guard let webView = targetWebView else {
            dismissBanner()
            return
        }
        webView.evaluateJavaScript(
            "if (typeof window.__prismRestoreOriginalPage === 'function') { window.__prismRestoreOriginalPage(); }",
            in: nil,
            in: .defaultClient
        ) { _ in }
        isShowingTranslated = false
        isTranslating = false
        statusMessage = "Showing original page"
    }

    public func dismissBanner() {
        isBannerVisible = false
        isTranslating = false
        showGoogleFallbackOffer = false
        statusMessage = nil
    }

    public func googleTranslateURL(for pageURL: URL) -> URL? {
        var components = URLComponents(string: "https://translate.google.com/translate")
        components?.queryItems = [
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: selectedTarget.code),
            URLQueryItem(name: "u", value: pageURL.absoluteString),
        ]
        return components?.url
    }
}
