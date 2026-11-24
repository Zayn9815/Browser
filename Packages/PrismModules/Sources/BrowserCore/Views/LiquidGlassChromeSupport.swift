import SwiftUI

public enum PrismBrandPalette {
    public static let obsidianBackground = Color(red: 10.0 / 255.0, green: 10.0 / 255.0, blue: 15.0 / 255.0)
    public static let obsidianElevated = Color(red: 18.0 / 255.0, green: 18.0 / 255.0, blue: 28.0 / 255.0)
    public static let crimsonAccent = Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0)
}

public extension View {
    /// Safe iOS 26.0 / 26.1+ bridge for SwiftUI's `tabViewBottomAccessory` API so `IPHONEOS_DEPLOYMENT_TARGET = 26.0`
    /// compiles cleanly under Xcode 26.2–26.6 where `isEnabled:` is gated at iOS 26.1+.
    @ViewBuilder
    func prismBottomAccessory<Content: View>(
        isVisible: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        if #available(iOS 26.1, *) {
            self.tabViewBottomAccessory(isEnabled: isVisible, content: content)
        } else {
            self.tabViewBottomAccessory {
                if isVisible {
                    content()
                }
            }
        }
    }
}
