import SwiftUI

public struct VaultLockOverlayView: View {
    @Bindable private var authService: BiometricAuthService
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
        ZStack {
            Color(red: 10.0 / 255.0, green: 10.0 / 255.0, blue: 15.0 / 255.0)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: authService.biometryIconName)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                }

                if let error = authService.lastErrorMessage, !error.isEmpty {
                    Text(error)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
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
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .disabled(isAuthenticating)
                    .buttonStyle(.glassProminent)
                    .tint(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
                }

                if authService.hasConfiguredPIN {
                    Button(showPINPad ? "Use \(authService.biometryLabel)" : "Use Custom PIN") {
                        withAnimation(.snappy) {
                            showPINPad.toggle()
                        }
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(28)
            .frame(maxWidth: 340)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
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
