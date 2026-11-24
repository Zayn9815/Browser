import PrismCore
import SwiftUI

public struct VaultLockOverlayView: View {
    @Bindable private var authService: BiometricAuthService
    @State private var themeEngine = PrismThemeEngine.shared
    private let title: String
    private let subtitle: String
    private let onUnlocked: (() -> Void)?

    @State private var pinInput = ""
    @State private var showPINPad = false
    @State private var isAuthenticating = false

    public init(
        authService: BiometricAuthService,
        title: String = "Private Vault Locked",
        subtitle: String = "Authenticate to access Private Incognito Tabs and encrypted Vault files.",
        onUnlocked: (() -> Void)? = nil
    ) {
        self.authService = authService
        self.title = title
        self.subtitle = subtitle
        self.onUnlocked = onUnlocked
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        ZStack {
            PrismAtmosphericWallpaperView(themeEngine: themeEngine)

            VStack(spacing: 22) {
                Image(systemName: authService.biometryIconName)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(tokens.accent)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(tokens.primaryText)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(tokens.secondaryText)
                        .multilineTextAlignment(.center)
                }

                if let error = authService.lastErrorMessage, !error.isEmpty {
                    Text(error)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(tokens.destructive)
                        .multilineTextAlignment(.center)
                }

                if showPINPad && authService.hasConfiguredPIN {
                    VStack(spacing: 12) {
                        SecureField("Enter Vault PIN", text: $pinInput)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 220)

                        Button {
                            if authService.unlockWithPIN(pinInput) {
                                pinInput = ""
                                onUnlocked?()
                            }
                        } label: {
                            Text("Unlock with PIN")
                                .font(.headline)
                                .foregroundStyle(tokens.accentText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(tokens.accent)
                    }
                } else {
                    Button {
                        Task { await triggerBiometricUnlock() }
                    } label: {
                        Label(
                            isAuthenticating ? "Authenticating…" : "Unlock with \(authService.biometryLabel)",
                            systemImage: authService.biometryIconName
                        )
                        .font(.headline)
                        .foregroundStyle(tokens.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .disabled(isAuthenticating)
                    .buttonStyle(.glassProminent)
                    .tint(tokens.accent)
                }

                if authService.hasConfiguredPIN {
                    Button(showPINPad ? "Use \(authService.biometryLabel)" : "Use Custom PIN") {
                        withAnimation(.snappy) {
                            showPINPad.toggle()
                        }
                    }
                    .foregroundStyle(tokens.primaryText)
                    .buttonStyle(.glass)
                }
            }
            .padding(28)
            .frame(maxWidth: 340)
            .prismGlassCard(cornerRadius: 28, prominent: true)
            .padding(.horizontal, 20)
        }
    }

    private func triggerBiometricUnlock() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let ok = await authService.authenticate()
        if ok {
            onUnlocked?()
        }
    }
}
