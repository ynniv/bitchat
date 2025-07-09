//
// NostrSettings.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// Utility class to access Nostr settings from anywhere in the app
class NostrSettings {
    
    // MARK: - Default Relay Configuration
    
    /// Default relay URLs used throughout the app
    static let defaultRelayURLs = [
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://relay.snort.social"
    ]
    
    /// Primary default relay URL (first in the list)
    static let primaryDefaultRelay = "wss://relay.damus.io"
    
    // MARK: - Settings Access
    
    /// Check if Nostr bridge is enabled
    static var isEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "NostrBridgeEnabled")
    }
    
    /// Get the configured primary relay URL (for single relay usage)
    static var relayURL: String {
        return UserDefaults.standard.string(forKey: "NostrRelayURL") ?? primaryDefaultRelay
    }
    
    /// Get all configured relay URLs (for multi-relay usage)
    static var relayURLs: [String] {
        if let saved = UserDefaults.standard.array(forKey: "NostrRelayURLs") as? [String], !saved.isEmpty {
            return saved
        }
        return defaultRelayURLs
    }
    
    /// Check if publishing to relays is enabled
    static var publishToRelays: Bool {
        return UserDefaults.standard.object(forKey: "NostrPublishToRelays") as? Bool ?? true
    }
    
    // MARK: - Relay Management
    
    /// Set the primary relay URL (updates both single and multi-relay settings)
    static func setRelayURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: "NostrRelayURL")
        
        // Also update the multi-relay list if this URL isn't already first
        var currentRelays = relayURLs
        if currentRelays.first != url {
            currentRelays.removeAll { $0 == url }
            currentRelays.insert(url, at: 0)
            UserDefaults.standard.set(currentRelays, forKey: "NostrRelayURLs")
        }
    }
    
    /// Set multiple relay URLs
    static func setRelayURLs(_ urls: [String]) {
        UserDefaults.standard.set(urls, forKey: "NostrRelayURLs")
        
        // Also update the primary relay to be the first one
        if let first = urls.first {
            UserDefaults.standard.set(first, forKey: "NostrRelayURL")
        }
    }
    
    /// Add a relay URL to the list
    static func addRelayURL(_ url: String) {
        var currentRelays = relayURLs
        if !currentRelays.contains(url) {
            currentRelays.append(url)
            setRelayURLs(currentRelays)
        }
    }
    
    /// Remove a relay URL from the list
    static func removeRelayURL(_ url: String) {
        var currentRelays = relayURLs
        currentRelays.removeAll { $0 == url }
        
        // Ensure we always have at least the default relay
        if currentRelays.isEmpty {
            currentRelays = [primaryDefaultRelay]
        }
        
        setRelayURLs(currentRelays)
    }
    
    /// Reset relay URLs to defaults
    static func resetRelayURLsToDefaults() {
        setRelayURLs(defaultRelayURLs)
    }
    
    /// Get the private key from Keychain
    static var privateKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "NostrPrivateKey",
            kSecAttrService as String: "bitchat",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let key = String(data: data, encoding: .utf8) {
            return key
        }
        
        return nil
    }
    
    /// Check if Nostr is fully configured (enabled with private key)
    static var isConfigured: Bool {
        return isEnabled && privateKey != nil
    }
}
