//
//  KeychainHelper.swift
//  CymaxPhoneOutMenubar
//
//  Securely stores credentials and grace period in an AES-256 encrypted file.
//  Uses PBKDF2 key derivation from hardware UUID.
//  Also cleans up any legacy Keychain items and UserDefaults from previous versions.
//

import Foundation
import Security
import CommonCrypto
import IOKit

struct KeychainHelper {

    private static let service = "com.cymatics.mixlink.subscription"
    private static let salt: [UInt8] = [0xC7, 0x3A, 0x71, 0xC5, 0x4D, 0x1E, 0xA1, 0x4B,
                                        0xA0, 0xB3, 0xE2, 0x9F, 0x58, 0x6D, 0x17, 0xC4]

    // MARK: - Credentials

    static func saveCredentials(email: String, password: String) {
        var blob = loadBlob()
        blob["email"] = email
        blob["password"] = password
        _ = saveBlob(blob)
    }

    static func loadCredentials() -> (email: String, password: String)? {
        let blob = loadBlob()
        guard let email = blob["email"] as? String, !email.isEmpty,
              let password = blob["password"] as? String, !password.isEmpty else {
            return nil
        }
        return (email, password)
    }

    static func clearCredentials() {
        let file = credentialFile()
        try? FileManager.default.removeItem(at: file)
        cleanupKeychain()
        cleanupUserDefaults()
    }

    static var hasSavedCredentials: Bool {
        return loadCredentials() != nil
    }

    // MARK: - Grace Period (stored in same encrypted blob)

    static func getLastVerifiedTime() -> Double {
        let blob = loadBlob()
        return blob["lastVerifiedAt"] as? Double ?? 0.0
    }

    static func setLastVerifiedTime(_ time: Double) {
        var blob = loadBlob()
        blob["lastVerifiedAt"] = time
        _ = saveBlob(blob)
    }

    static func clearLastVerifiedTime() {
        var blob = loadBlob()
        blob.removeValue(forKey: "lastVerifiedAt")
        _ = saveBlob(blob)
    }

    // MARK: - Internal Blob Management

    private static func loadBlob() -> [String: Any] {
        guard let json = loadAndDecrypt(),
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private static func saveBlob(_ blob: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: blob),
              let json = String(data: data, encoding: .utf8) else { return false }
        return encryptAndSave(json)
    }

    // MARK: - File Path

    private static func credentialFile() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Cymatics/MixLink", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("auth.dat")
    }

    // MARK: - Hardware UUID

    private static func hardwareUUID() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/AppleACPIPlatformExpert")
        guard entry != MACH_PORT_NULL else { return nil }
        defer { IOObjectRelease(entry) }

        guard let cfUUID = IORegistryEntryCreateCFProperty(entry, "IOPlatformUUID" as CFString,
                                                            kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else {
            return nil
        }
        return cfUUID
    }

    // MARK: - Key Derivation

    private static func deriveKey() -> Data? {
        guard let uuid = hardwareUUID() else { return nil }
        let passphrase = uuid + "::cymatics.fm/mixlink"
        guard let passphraseData = passphrase.data(using: .utf8) else { return nil }

        var derivedKey = Data(count: kCCKeySizeAES256)
        let result = derivedKey.withUnsafeMutableBytes { keyPtr in
            passphraseData.withUnsafeBytes { passPtr in
                salt.withUnsafeBufferPointer { saltPtr in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         passPtr.baseAddress!.assumingMemoryBound(to: Int8.self),
                                         passphraseData.count,
                                         saltPtr.baseAddress!, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                         100_000,
                                         keyPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                                         kCCKeySizeAES256)
                }
            }
        }
        return result == kCCSuccess ? derivedKey : nil
    }

    // MARK: - Encrypt / Decrypt

    private static func encryptAndSave(_ plaintext: String) -> Bool {
        guard let key = deriveKey(),
              let plaintextData = plaintext.data(using: .utf8) else { return false }

        var iv = Data(count: kCCBlockSizeAES128)
        let ivResult = iv.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, kCCBlockSizeAES128, $0.baseAddress!) }
        guard ivResult == errSecSuccess else { return false }

        let bufferSize = plaintextData.count + kCCBlockSizeAES128
        var ciphertext = Data(count: bufferSize)
        var bytesEncrypted = 0

        let status = ciphertext.withUnsafeMutableBytes { cipherPtr in
            plaintextData.withUnsafeBytes { plainPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(CCOperation(kCCEncrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyPtr.baseAddress!, key.count,
                                ivPtr.baseAddress!,
                                plainPtr.baseAddress!, plaintextData.count,
                                cipherPtr.baseAddress!, bufferSize,
                                &bytesEncrypted)
                    }
                }
            }
        }

        guard status == kCCSuccess else { return false }
        ciphertext.count = bytesEncrypted

        var output = Data()
        output.append(iv)
        output.append(ciphertext)

        let file = credentialFile()
        do {
            try output.write(to: file)
            return true
        } catch {
            return false
        }
    }

    private static func loadAndDecrypt() -> String? {
        let file = credentialFile()
        guard let fileData = try? Data(contentsOf: file),
              fileData.count > kCCBlockSizeAES128,
              let key = deriveKey() else { return nil }

        let iv = fileData.prefix(kCCBlockSizeAES128)
        let ciphertext = fileData.dropFirst(kCCBlockSizeAES128)

        let bufferSize = ciphertext.count + kCCBlockSizeAES128
        var plaintext = Data(count: bufferSize)
        var bytesDecrypted = 0

        let status = plaintext.withUnsafeMutableBytes { plainPtr in
            ciphertext.withUnsafeBytes { cipherPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(CCOperation(kCCDecrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyPtr.baseAddress!, key.count,
                                ivPtr.baseAddress!,
                                cipherPtr.baseAddress!, ciphertext.count,
                                plainPtr.baseAddress!, bufferSize,
                                &bytesDecrypted)
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        plaintext.count = bytesDecrypted
        return String(data: plaintext, encoding: .utf8)
    }

    // MARK: - Legacy Cleanup

    private static func cleanupKeychain() {
        for account in ["cymatics_email", "cymatics_password"] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(query as CFDictionary)

            let dpQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecUseDataProtectionKeychain as String: true
            ]
            SecItemDelete(dpQuery as CFDictionary)
        }
    }

    private static func cleanupUserDefaults() {
        // Remove legacy plain-text grace period from UserDefaults
        UserDefaults.standard.removeObject(forKey: "com.cymatics.mixlink.lastVerifiedAt")
    }
}
