import PrismCore
import SwiftUI

@MainActor
public enum PrismBrandPalette {
    public static var obsidianBackground: Color { PrismThemeEngine.shared.tokens.canvasBackground }
    public static var obsidianElevated: Color { PrismThemeEngine.shared.tokens.elevatedSurface }
    public static var crimsonAccent: Color { PrismThemeEngine.shared.tokens.accent }
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
