import CryptoKit
import Foundation
import LocalAuthentication
import Observation
import Security

@Observable
@MainActor
public final class BiometricAuthService {
    public static let shared = BiometricAuthService()

    public private(set) var isPrivateUnlocked = false
    public private(set) var biometryType: LABiometryType = .none
    public private(set) var hasConfiguredPIN = false
    public private(set) var lastErrorMessage: String?

    private let keychainService = "com.prismdm.ios.vault.pin"
    private let keychainAccount = "private-vault-pin-hash"
    private let pinSaltPrefix = "prismdm.v1.pin."

    public init() {
        refreshCapabilities()
    }

    public func refreshCapabilities() {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        biometryType = context.biometryType
        hasConfiguredPIN = readPINHashFromKeychain() != nil
    }

    public var biometryLabel: String {
        switch biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "Device Passcode"
        @unknown default:
            return "Biometrics"
        }
    }

    public var biometryIconName: String {
        switch biometryType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .none:
            return "lock.fill"
        @unknown default:
            return "lock.shield.fill"
        }
    }

    public func lock() {
        isPrivateUnlocked = false
        lastErrorMessage = nil
    }

    @discardableResult
    public func authenticate(reason: String = "Unlock PrismDM Private Vault & Incognito Tabs") async -> Bool {
        lastErrorMessage = nil
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"

        var authError: NSError?
        let policy: LAPolicy
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) {
            policy = .deviceOwnerAuthentication
        } else if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) {
            policy = .deviceOwnerAuthentication
        } else {
            lastErrorMessage = authError?.localizedDescription ?? "Biometric or passcode authentication is unavailable."
            return false
        }

        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)
            if success {
                isPrivateUnlocked = true
            }
            return success
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    public func configurePIN(_ pin: String) -> Bool {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4, trimmed.allSatisfy(\.isNumber) else {
            lastErrorMessage = "PIN must be at least 4 digits."
            return false
        }
        let digest = hashPIN(trimmed)
        let saved = savePINHashToKeychain(digest)
        hasConfiguredPIN = saved
        if !saved {
            lastErrorMessage = "Unable to store PIN securely in Keychain."
        } else {
            lastErrorMessage = nil
        }
        return saved
    }

    @discardableResult
    public func unlockWithPIN(_ pin: String) -> Bool {
        guard let stored = readPINHashFromKeychain() else {
            lastErrorMessage = "No custom PIN is configured."
            return false
        }
        let candidate = hashPIN(pin.trimmingCharacters(in: .whitespacesAndNewlines))
        if constantTimeEqual(stored, candidate) {
            isPrivateUnlocked = true
            lastErrorMessage = nil
            return true
        }
        lastErrorMessage = "Incorrect PIN. Try again."
        return false
    }

    public func removeConfiguredPIN() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        hasConfiguredPIN = false
    }

    // MARK: - Keychain & Hashing Helpers

    private func hashPIN(_ pin: String) -> Data {
        let input = Data((pinSaltPrefix + pin).utf8)
        return Data(SHA256.hash(data: input))
    }

    private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(lhs, rhs) {
            diff |= a ^ b
        }
        return diff == 0
    }

    private func savePINHashToKeychain(_ data: Data) -> Bool {
        removeConfiguredPIN()
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData: data,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func readPINHashFromKeychain() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return data
    }
}
