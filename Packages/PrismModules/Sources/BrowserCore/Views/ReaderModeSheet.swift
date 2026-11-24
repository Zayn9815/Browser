import SwiftUI
import WebKit

public enum ReaderTheme: String, CaseIterable, Identifiable, Sendable {
    case obsidian = "Obsidian"
    case sepia = "Sepia"
    case paper = "Paper"

    public var id: String { rawValue }

    var backgroundHex: String {
        switch self {
        case .obsidian: return "#0A0A0F"
        case .sepia: return "#F5EEDB"
        case .paper: return "#FFFFFF"
        }
    }

    var textHex: String {
        switch self {
        case .obsidian: return "#ECEDF2"
        case .sepia: return "#3B2F23"
        case .paper: return "#16161B"
        }
    }

    var secondaryHex: String {
        switch self {
        case .obsidian: return "#9A9DAD"
        case .sepia: return "#786552"
        case .paper: return "#63636D"
        }
    }
}

public struct ReaderModeSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let article: ExtractedReaderArticle

    @State private var theme: ReaderTheme = .obsidian
    @State private var fontSizePoints: Double = 18

    public init(article: ExtractedReaderArticle) {
        self.article = article
    }

    public var body: some View {
        NavigationStack {
            ReaderHTMLWebView(
                html: renderedHTML,
                backgroundColorHex: theme.backgroundHex
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(article.siteName.isEmpty ? "Reader Mode" : article.siteName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 10) {
                        Button {
                            fontSizePoints = max(14, fontSizePoints - 2)
                        } label: {
                            Image(systemName: "textformat.size.smaller")
                        }
                        Button {
                            fontSizePoints = min(28, fontSizePoints + 2)
                        } label: {
                            Image(systemName: "textformat.size.larger")
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    Picker("Theme", selection: $theme) {
                        ForEach(ReaderTheme.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var renderedHTML: String {
        let escapedTitle = escapeHTML(article.title)
        let escapedByline = escapeHTML(article.byline)
        let escapedSite = escapeHTML(article.siteName)
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=2.0">
          <style>
            :root { color-scheme: \(theme == .obsidian ? "dark" : "light"); }
            body {
              margin: 0;
              padding: 20px 20px 56px 20px;
              background: \(theme.backgroundHex);
              color: \(theme.textHex);
              font-family: -apple-system, BlinkMacSystemFont, "New York", Georgia, serif;
              font-size: \(Int(fontSizePoints))px;
              line-height: 1.65;
              word-wrap: break-word;
            }
            header {
              margin-bottom: 24px;
              padding-bottom: 16px;
              border-bottom: 1px solid rgba(128,128,140,0.28);
            }
            .site {
              font-family: -apple-system, sans-serif;
              font-size: 12px;
              font-weight: 600;
              letter-spacing: 0.06em;
              text-transform: uppercase;
              color: #DC143C;
              margin-bottom: 8px;
            }
            h1 {
              font-size: 1.65em;
              line-height: 1.22;
              margin: 0 0 10px 0;
            }
            .byline {
              font-family: -apple-system, sans-serif;
              font-size: 13px;
              color: \(theme.secondaryHex);
            }
            img, figure {
              max-width: 100%;
              height: auto;
              border-radius: 12px;
            }
            pre, code {
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              font-size: 0.88em;
              overflow-x: auto;
            }
            blockquote {
              border-left: 3px solid #DC143C;
              margin-left: 0;
              padding-left: 14px;
              color: \(theme.secondaryHex);
            }
            a { color: #DC143C; }
          </style>
        </head>
        <body>
          <header>
            <div class="site">\(escapedSite)</div>
            <h1>\(escapedTitle)</h1>
            \(escapedByline.isEmpty ? "" : "<div class=\"byline\">\(escapedByline)</div>")
          </header>
          <article>\(article.contentHTML)</article>
        </body>
        </html>
        """
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private struct ReaderHTMLWebView: UIViewRepresentable {
    let html: String
    let backgroundColorHex: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastHTML: String = ""
    }
}
