import Foundation
import Security
import SwiftUI

/// The user's own photo-service API keys, kept in the login Keychain.
///
/// Lurent is open source, so no build carries a key. Pexels works without one
/// through the shared caching Worker; a key of your own skips it and talks to
/// api.pexels.com directly, on your own quota. Unsplash has no shared fallback —
/// its API terms bar a shared key for a wallpaper app — so it needs your own.
enum APIKeyService: String, CaseIterable, Identifiable {
    case pexels, unsplash
    var id: String { rawValue }
}

enum APIKeys {
    private static let keychainService = "app.lurent.api-keys"

    static func key(for service: APIKeyService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: service.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { return nil }
        return key
    }

    /// Stores `key`, or removes the entry when it is empty.
    static func setKey(_ key: String, for service: APIKeyService) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: service.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Lurent › Settings… (⌘,): where the keys are entered.
struct APIKeysSettingsView: View {
    @State private var pexels = APIKeys.key(for: .pexels) ?? ""
    @State private var unsplash = APIKeys.key(for: .unsplash) ?? ""

    var body: some View {
        Form {
            Section {
                SecureField("Pexels-API-Key", text: $pexels)
                    .onChange(of: pexels) { APIKeys.setKey(pexels, for: .pexels) }
                Text("Optional. Ohne Key läuft die Pexels-Suche über den gemeinsamen Lurent-Cache.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Key holen: pexels.com/api", destination: URL(string: "https://www.pexels.com/api/")!)
                    .font(.caption)
            }
            Section {
                SecureField("Unsplash-Access-Key", text: $unsplash)
                    .onChange(of: unsplash) { APIKeys.setKey(unsplash, for: .unsplash) }
                Text("Nötig für die Unsplash-Suche.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Key holen: unsplash.com/developers", destination: URL(string: "https://unsplash.com/developers")!)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
