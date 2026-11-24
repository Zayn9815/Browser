import Foundation
import Observation
import WebKit

public struct GoogleAccountProfile: Codable, Sendable, Equatable {
    public var displayName: String
    public var email: String
    public var signedInAt: Date

    public init(displayName: String, email: String, signedInAt: Date = .now) {
        self.displayName = displayName
        self.email = email
        self.signedInAt = signedInAt
    }

    public var initials: String {
        let parts = displayName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap { $0.first.map { String($0).uppercased() } }
        if !parts.isEmpty {
            return parts.joined()
        }
        if let first = email.first {
            return String(first).uppercased()
        }
        return "G"
    }
}

@Observable
@MainActor
public final class GoogleAccountManager {
    public static let shared = GoogleAccountManager()

    public private(set) var profile: GoogleAccountProfile?
    public private(set) var isSignedIn: Bool = false
    public private(set) var isCheckingSession: Bool = false

    private let profileStorageKey = "prismdm.v1.googleAccountProfile"
    private let googleAuthCookieNames: Set<String> = [
        "SID", "HSID", "SSID", "APISID", "SAPISID",
        "__Secure-1PSID", "__Secure-3PSID", "__Secure-1PAPISID", "__Secure-3PAPISID"
    ]

    public init() {
        if let data = UserDefaults.standard.data(forKey: profileStorageKey),
           let saved = try? JSONDecoder().decode(GoogleAccountProfile.self, from: data) {
            self.profile = saved
            self.isSignedIn = true
        }
    }

    public func refreshSessionStatus() async {
        isCheckingSession = true
        defer { isCheckingSession = false }

        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let now = Date.now
        let hasValidGoogleSession = cookies.contains { cookie in
            let domain = cookie.domain.lowercased()
            let isGoogleDomain = domain == "google.com" || domain.hasSuffix(".google.com")
            guard isGoogleDomain, googleAuthCookieNames.contains(cookie.name) else {
                return false
            }
            if let expires = cookie.expiresDate, expires < now {
                return false
            }
            return !cookie.value.isEmpty
        }

        if hasValidGoogleSession {
            isSignedIn = true
            if profile == nil {
                let fallback = GoogleAccountProfile(
                    displayName: "Google Account",
                    email: "Signed in across Google services"
                )
                profile = fallback
                persistProfile(fallback)
            }
        } else {
            isSignedIn = false
            profile = nil
            UserDefaults.standard.removeObject(forKey: profileStorageKey)
        }
    }

    public func recordSignedIn(displayName: String?, email: String?) {
        let cleanedEmail = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedName = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedName: String
        if !cleanedName.isEmpty {
            resolvedName = cleanedName
        } else if !cleanedEmail.isEmpty, let local = cleanedEmail.split(separator: "@").first {
            resolvedName = String(local)
        } else {
            resolvedName = "Google Account"
        }

        let resolvedEmail = cleanedEmail.isEmpty ? "Signed in across Google services" : cleanedEmail
        let updated = GoogleAccountProfile(displayName: resolvedName, email: resolvedEmail, signedInAt: .now)
        profile = updated
        isSignedIn = true
        persistProfile(updated)
    }

    public func signOut() async {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await cookieStore.allCookies()
        let targetSuffixes = ["google.com", "youtube.com", "googleapis.com", "gstatic.com", "googleusercontent.com"]

        for cookie in cookies {
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if targetSuffixes.contains(where: { domain == $0 || domain.hasSuffix(".\($0)") }) {
                await cookieStore.delete(cookie)
            }
        }

        profile = nil
        isSignedIn = false
        UserDefaults.standard.removeObject(forKey: profileStorageKey)
    }

    private func persistProfile(_ profile: GoogleAccountProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileStorageKey)
        }
    }
}
