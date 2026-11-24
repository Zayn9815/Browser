import Foundation

public enum PlayerAspectMode: String, CaseIterable, Sendable, Identifiable {
    case fit = "Fit"
    case fill = "Fill"
    case stretch = "Stretch"

    public var id: String { rawValue }
}

public struct PlayerMediaTrack: Identifiable, Sendable, Equatable, Hashable {
    public let id: Int
    public let title: String
    public let languageCode: String?
    public let isDefault: Bool

    public init(
        id: Int,
        title: String,
        languageCode: String? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.title = title
        self.languageCode = languageCode
        self.isDefault = isDefault
    }

    public var displayName: String {
        if let languageCode, !languageCode.isEmpty, !title.localizedCaseInsensitiveContains(languageCode) {
            return "\(title) (\(languageCode.uppercased()))"
        }
        return title
    }
}

public enum PlayerPlaybackSpeed: Float, CaseIterable, Sendable, Identifiable {
    case half = 0.5
    case threeQuarters = 0.75
    case normal = 1.0
    case oneAndQuarter = 1.25
    case oneAndHalf = 1.5
    case double = 2.0
    case twoAndHalf = 2.5

    public var id: Float { rawValue }

    public var label: String {
        rawValue == floor(rawValue) ? "\(Int(rawValue))x" : "\(rawValue)x"
    }
}
