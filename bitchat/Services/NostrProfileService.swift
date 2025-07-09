//
// NostrProfileService.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import Network
import CryptoKit

/// Nostr user profile structure (kind 0 event)
struct NostrProfile: Codable {
    let name: String?
    let about: String?
    let picture: String?
    let nip05: String?
    let display_name: String?
    let website: String?
    let banner: String?
    let lud06: String?
    let lud16: String?
    
    // Custom keys for additional data
    private let additionalData: [String: String]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decodeIfPresent(String.self, forKey: .name)
        about = try container.decodeIfPresent(String.self, forKey: .about)
        picture = try container.decodeIfPresent(String.self, forKey: .picture)
        nip05 = try container.decodeIfPresent(String.self, forKey: .nip05)
        display_name = try container.decodeIfPresent(String.self, forKey: .display_name)
        website = try container.decodeIfPresent(String.self, forKey: .website)
        banner = try container.decodeIfPresent(String.self, forKey: .banner)
        lud06 = try container.decodeIfPresent(String.self, forKey: .lud06)
        lud16 = try container.decodeIfPresent(String.self, forKey: .lud16)
        
        // Capture any additional fields
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKeys.self)
        var extra: [String: String] = [:]
        
        for key in dynamicContainer.allKeys {
            if !CodingKeys.allCases.map(\.stringValue).contains(key.stringValue) {
                if let value = try? dynamicContainer.decode(String.self, forKey: key) {
                    extra[key.stringValue] = value
                }
            }
        }
        
        additionalData = extra.isEmpty ? nil : extra
    }
    
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case name, about, picture, nip05, display_name, website, banner, lud06, lud16
    }
    
    private struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?
        
        init?(stringValue: String) {
            self.stringValue = stringValue
        }
        
        init?(intValue: Int) {
            return nil
        }
    }
    
    /// Get the best display name for this profile
    var bestDisplayName: String? {
        // Try display_name first
        if let displayName = display_name, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Fall back to name
        if let name = name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // No good name data available
        return nil
    }
    
    /// Get a short identifier for this profile
    var shortIdentifier: String? {
        if let name = name, name.count <= 20 {
            return name
        }
        if let displayName = display_name, displayName.count <= 20 {
            return displayName
        }
        return name?.prefix(20).description ?? display_name?.prefix(20).description
    }
}

/// WebSocket client for fetching Nostr profiles
class NostrProfileClient {
    private let url: URL
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession.shared
    private var pendingRequests: [String: (NostrProfile?) -> Void] = [:]
    private var subscriptionId: String?
    
    init(url: URL) {
        self.url = url
    }
    
    func connect() async throws {
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Start receiving messages
        Task {
            await receiveMessages()
        }
    }
    
    func disconnect() {
        // Close any pending subscriptions
        if let subId = subscriptionId {
            Task {
                try? await closeSubscription(subId)
            }
        }
        
        webSocketTask?.cancel()
        webSocketTask = nil
        
        // Clear pending requests
        for (_, completion) in pendingRequests {
            completion(nil)
        }
        pendingRequests.removeAll()
    }
    
    /// Fetch a profile for a given pubkey
    func fetchProfile(pubkey: String) async -> NostrProfile? {
        return await withCheckedContinuation { continuation in
            fetchProfile(pubkey: pubkey) { profile in
                continuation.resume(returning: profile)
            }
        }
    }
    
    private func fetchProfile(pubkey: String, completion: @escaping (NostrProfile?) -> Void) {
        guard webSocketTask != nil else {
            completion(nil)
            return
        }
        
        // Store the completion handler
        pendingRequests[pubkey] = completion
        
        // Create a subscription for this profile
        let subId = "profile_\(pubkey.prefix(8))_\(Int.random(in: 1000...9999))"
        subscriptionId = subId
        
        let subscription: [Any] = [
            "REQ",
            subId,
            [
                "kinds": [0],
                "authors": [pubkey],
                "limit": 1
            ]
        ]
        
        Task {
            do {
                let data = try JSONSerialization.data(withJSONObject: subscription)
                let string = String(data: data, encoding: .utf8)!
                try await webSocketTask?.send(.string(string))
                
                // Set a timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    if self.pendingRequests[pubkey] != nil {
                        self.pendingRequests.removeValue(forKey: pubkey)
                        completion(nil)
                    }
                }
            } catch {
                print("[NOSTR] Failed to send profile request: \(error)")
                pendingRequests.removeValue(forKey: pubkey)
                completion(nil)
            }
        }
    }
    
    private func closeSubscription(_ subId: String) async throws {
        let closeMessage: [Any] = ["CLOSE", subId]
        let data = try JSONSerialization.data(withJSONObject: closeMessage)
        let string = String(data: data, encoding: .utf8)!
        try await webSocketTask?.send(.string(string))
    }
    
    private func receiveMessages() async {
        guard let webSocketTask = webSocketTask else { return }
        
        do {
            let message = try await webSocketTask.receive()
            
            switch message {
            case .string(let text):
                handleMessage(text)
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    handleMessage(text)
                }
            @unknown default:
                break
            }
            
            // Continue receiving
            await receiveMessages()
        } catch {
            print("[NOSTR] NostrProfileClient WebSocket error: \(error)")
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let messageType = json.first as? String else { return }
        
        switch messageType {
        case "EVENT":
            handleEventMessage(json)
        case "EOSE":
            // End of stored events - no more profiles coming
            if json.count >= 2, let subId = json[1] as? String {
                handleEndOfEvents(subId)
            }
        case "NOTICE":
            if let notice = json[1] as? String {
                print("[NOSTR] Profile relay notice: \(notice)")
            }
        default:
            break
        }
    }
    
    private func handleEventMessage(_ json: [Any]) {
        guard json.count >= 3,
              let subId = json[1] as? String,
              let eventDict = json[2] as? [String: Any],
              let kind = eventDict["kind"] as? Int,
              kind == 0,  // Profile events
              let pubkey = eventDict["pubkey"] as? String,
              let content = eventDict["content"] as? String else { return }
        
        // Parse the profile content (JSON)
        guard let contentData = content.data(using: .utf8),
              let profile = try? JSONDecoder().decode(NostrProfile.self, from: contentData) else {
            print("[NOSTR] Failed to parse profile content for pubkey: \(pubkey.prefix(8))...")
            return
        }
        
        // Complete the pending request
        if let completion = pendingRequests.removeValue(forKey: pubkey) {
            completion(profile)
        }
    }
    
    private func handleEndOfEvents(_ subId: String) {
        // Close the subscription
        Task {
            try? await closeSubscription(subId)
        }
        
        // If we didn't get a profile, complete with nil
        if let pubkey = pendingRequests.keys.first(where: { _ in subscriptionId == subId }) {
            if let completion = pendingRequests.removeValue(forKey: pubkey) {
                completion(nil)
            }
        }
    }
}

/// Service for fetching and caching Nostr profiles
class NostrProfileService {
    private let relayClients: [NostrProfileClient]
    private var profileCache: [String: (profile: NostrProfile?, timestamp: Date)] = [:]
    private let cacheTimeout: TimeInterval = 300 // 5 minutes
    private let maxCacheSize = 1000
    
    init(relayURLs: [String] = NostrSettings.relayURLs) {
        self.relayClients = relayURLs.compactMap { urlString in
            guard let url = URL(string: urlString) else { return nil }
            return NostrProfileClient(url: url)
        }
    }
    
    /// Start the profile service
    func start() async {
        // Connect to all relays
        await withTaskGroup(of: Void.self) { group in
            for client in relayClients {
                group.addTask {
                    try? await client.connect()
                }
            }
        }
        
        print("[NOSTR] NostrProfileService started with \(relayClients.count) relays")
    }
    
    /// Stop the profile service
    func stop() {
        for client in relayClients {
            client.disconnect()
        }
        print("[NOSTR] NostrProfileService stopped")
    }
    
    /// Get profile for a pubkey (checks cache first)
    func getProfile(for pubkey: String) async -> NostrProfile? {
        // Check cache first
        if let cached = profileCache[pubkey] {
            let age = Date().timeIntervalSince(cached.timestamp)
            if age < cacheTimeout {
                return cached.profile
            } else {
                // Cache expired
                profileCache.removeValue(forKey: pubkey)
            }
        }
        
        // Fetch from relays
        let profile = await fetchProfileFromRelays(pubkey: pubkey)
        
        // Cache the result (even if nil)
        cacheProfile(profile, for: pubkey)
        
        return profile
    }
    
    /// Get display name for a pubkey - now smarter about preserving existing names
    func getDisplayName(for pubkey: String, fallbackName: String? = nil) async -> String? {
        let profile = await getProfile(for: pubkey)
        let nostrName = profile?.bestDisplayName
        
        // If we have good Nostr profile data, use it
        if let nostrName = nostrName, !nostrName.isEmpty {
            return nostrName
        }
        
        // If no good Nostr data and we have a fallback name, preserve it
        if let fallbackName = fallbackName, !fallbackName.isEmpty {
            return nil // Signal to caller to keep existing name
        }
        
        // No good data anywhere
        return nil
    }
    
    /// Get short display name for a pubkey (max 20 chars)
    func getShortDisplayName(for pubkey: String) async -> String? {
        let profile = await getProfile(for: pubkey)
        return profile?.shortIdentifier
    }
    
    private func fetchProfileFromRelays(pubkey: String) async -> NostrProfile? {
        // Try each relay until we get a profile
        for client in relayClients {
            if let profile = await client.fetchProfile(pubkey: pubkey) {
                return profile
            }
        }
        return nil
    }
    
    private func cacheProfile(_ profile: NostrProfile?, for pubkey: String) {
        // Manage cache size
        if profileCache.count >= maxCacheSize {
            // Remove oldest entries
            let sortedKeys = profileCache.keys.sorted { key1, key2 in
                let time1 = profileCache[key1]?.timestamp ?? Date.distantPast
                let time2 = profileCache[key2]?.timestamp ?? Date.distantPast
                return time1 < time2
            }
            
            let keysToRemove = sortedKeys.prefix(maxCacheSize / 4) // Remove 25%
            for key in keysToRemove {
                profileCache.removeValue(forKey: key)
            }
        }
        
        profileCache[pubkey] = (profile: profile, timestamp: Date())
    }
    
    /// Clear the profile cache
    func clearCache() {
        profileCache.removeAll()
    }
    
    /// Get cache statistics
    var cacheStats: (count: Int, size: Int) {
        return (count: profileCache.count, size: maxCacheSize)
    }
}

/// Extension to detect dual-signed messages and get display names
extension BitchatMessage {
    
    /// Check if this message has a Nostr signature (is dual-signed)
    var hasDualSignature: Bool {
        return dualSignature != nil
    }
    
    /// Extract Nostr pubkey from dual-signed message
    var nostrPubkey: String? {
        return dualSignature?.nostrPubkey
    }
    
    /// Get display name from Nostr profile (async)
    func getNostrDisplayName() async -> String? {
        guard let pubkey = nostrPubkey else { return nil }
        return await NostrProfileManager.shared.getDisplayName(for: pubkey)
    }
    
    /// Get short display name from Nostr profile (async)
    func getNostrShortDisplayName() async -> String? {
        guard let pubkey = nostrPubkey else { return nil }
        return await NostrProfileManager.shared.getShortDisplayName(for: pubkey)
    }
    
    /// Get full Nostr profile (async)
    func getNostrProfile() async -> NostrProfile? {
        guard let pubkey = nostrPubkey else { return nil }
        return await NostrProfileManager.shared.getProfile(for: pubkey)
    }
    
    /// Get the best display name for this message (prefers Nostr profile)
    func getBestDisplayName() async -> String {
        if let nostrDisplayName = await getNostrDisplayName() {
            return nostrDisplayName
        }
        return sender // Fall back to original sender
    }
    
    /// Get a short display name for this message (prefers Nostr profile)
    func getBestShortDisplayName() async -> String {
        if let nostrShortDisplayName = await getNostrShortDisplayName() {
            return nostrShortDisplayName
        }
        return String(sender.prefix(20)) // Fall back to truncated sender
    }
    
    /// Create a copy of this message with updated display name from Nostr profile
    func withNostrDisplayName() async -> BitchatMessage {
        guard let nostrDisplayName = await getNostrDisplayName() else {
            return self // Return unchanged if no Nostr profile found
        }
        
        return BitchatMessage(
            sender: nostrDisplayName,
            content: content,
            timestamp: timestamp,
            isRelay: isRelay,
            originalSender: originalSender,
            isPrivate: isPrivate,
            recipientNickname: recipientNickname,
            senderPeerID: senderPeerID,
            mentions: mentions,
            room: room,
            encryptedContent: encryptedContent,
            isEncrypted: isEncrypted,
            dualSignature: dualSignature
        )
    }
}

/// Extension to Character for hex digit checking
private extension Character {
    var isHexDigit: Bool {
        return isNumber || ("a"..."f").contains(lowercased()) || ("A"..."F").contains(self)
    }
}

/// Global profile service instance
class NostrProfileManager {
    static let shared = NostrProfileManager()
    private var profileService: NostrProfileService?
    
    private init() {}
    
    func start() async {
        if profileService == nil {
            profileService = NostrProfileService()
            await profileService?.start()
        }
    }
    
    func stop() {
        profileService?.stop()
        profileService = nil
    }
    
    func getDisplayName(for pubkey: String, fallbackName: String? = nil) async -> String? {
        return await profileService?.getDisplayName(for: pubkey, fallbackName: fallbackName)
    }
    
    func getShortDisplayName(for pubkey: String) async -> String? {
        return await profileService?.getShortDisplayName(for: pubkey)
    }
    
    func getProfile(for pubkey: String) async -> NostrProfile? {
        return await profileService?.getProfile(for: pubkey)
    }
}
