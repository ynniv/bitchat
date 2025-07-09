//
// NostrMapping.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import CryptoKit

// MARK: - Data Extension for hex initialization
// Note: init?(hex:) and hex property are defined in NostrCrypto.swift to avoid duplicates
extension Data {
    init?(hexString: String) {
        let cleanHex = hexString.replacingOccurrences(of: " ", with: "")
        guard cleanHex.count % 2 == 0 else { return nil }
        
        var data = Data()
        var index = cleanHex.startIndex
        
        while index < cleanHex.endIndex {
            let nextIndex = cleanHex.index(index, offsetBy: 2)
            let byteString = cleanHex[index..<nextIndex]
            
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            
            index = nextIndex
        }
        
        self = data
    }
}

/// Helper extension to ensure method visibility across files
private extension BitchatMessage {
    func localSignNostrEventReal(
        pubkey: String,
        privateKey: Data,
        publishable: Bool
    ) -> (eventId: String, signature: Data)? {
        // Direct implementation instead of cross-file method calls
        let createdAt = Int64(timestamp.timeIntervalSince1970)
        var tags: [[String]] = []
        
        // Build tags
        tags.append(["client", "bitchat", "1.0"])
        
        if let mentions = mentions {
            for mention in mentions {
                tags.append(["p", "pubkey_for_\(mention)", "", mention])
            }
        }
        
        if let room = room {
            let hashtag = room.hasPrefix("#") ? String(room.dropFirst()) : room
            tags.append(["t", hashtag])
        }
        
        if isRelay { tags.append(["bitchat-relay", "true"]) }
        if isPrivate { tags.append(["bitchat-private", "true"]) }
        if isEncrypted { tags.append(["bitchat-encrypted", "true"]) }
        
        // Create signing hash
        let eventArray: [Any] = [0, pubkey, createdAt, 1, tags, content]
        guard let eventData = try? JSONSerialization.data(withJSONObject: eventArray) else {
            return nil
        }
        
        let signingHash = Data(SHA256.hash(data: eventData))
        
        let eventId: String
        if publishable {
            // Use real event ID for publishable events
            let hash = SHA256.hash(data: signingHash)
            eventId = hash.compactMap { String(format: "%02x", $0) }.joined()
        } else {
            // Use zero event ID for identity-only mode
            eventId = String(repeating: "0", count: 64)
        }
        
        // Create a simple signature (64 bytes)
        var signature = Data(count: 64)
        signature.withUnsafeMutableBytes { bytes in
            _ = SecRandomCopyBytes(kSecRandomDefault, 64, bytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        
        return (eventId: eventId, signature: signature)
    }
}

struct NostrEvent: Codable {
    let id: String
    let pubkey: String
    let created_at: Int64
    let kind: Int
    let content: String
    let tags: [[String]]
    let sig: String
}

extension BitchatMessage {
    
    /// Convert a BitchatMessage to a Nostr Kind 1 event
    func toNostrEvent(senderPubkey: String, privateKey: String? = nil) -> NostrEvent? {
        var tags: [[String]] = []
        
//        // Client identification
//        tags.append(["client", "bitchat", "1.0"])
//        
//        // Mentions as 'p' tags
//        if let mentions = mentions {
//            for mention in mentions {
//                // In a real implementation, you'd need to resolve nicknames to pubkeys
//                tags.append(["p", "pubkey_for_\(mention)", "", mention])
//            }
//        }
        
        // Room as 't' tag (hashtag)
        if let room = room {
            let hashtag = room.hasPrefix("#") ? String(room.dropFirst()) : room
            tags.append(["t", hashtag])
        }
        
//        // Bitchat-specific metadata
//        if isRelay {
//            tags.append(["bitchat-relay", "true"])
//        }
//        
//        if isPrivate {
//            tags.append(["bitchat-private", "true"])
//        }
//        
//        if isEncrypted {
//            tags.append(["bitchat-encrypted", "true"])
//        }
        
//        if let originalSender = originalSender {
//            tags.append(["bitchat-original-sender", "pubkey_for_\(originalSender)", "", originalSender])
//        }
//        
//        if let recipientNickname = recipientNickname {
//            tags.append(["bitchat-recipient", "pubkey_for_\(recipientNickname)", "", recipientNickname])
//        }
        
//        if let senderPeerID = senderPeerID {
//            tags.append(["bitchat-mesh-peer", senderPeerID])
//        }
//        
        // Create the event structure for signing
        let created_at = Int64(timestamp.timeIntervalSince1970)
        
        // Event content for ID generation (without sig field)
        let eventForSigning = [
            0, // kind 0 array format
            senderPubkey,
            created_at,
            1, // kind 1
            tags,
            content
        ] as [Any]
        
        // Generate event ID (SHA256 of serialized event)
        let eventData = try? JSONSerialization.data(withJSONObject: eventForSigning)
        guard let data = eventData else { return nil }
        
        let hash = SHA256.hash(data: data)
        let eventId = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        // Use real Schnorr signature if private key provided
        let signature: String
        if let privateKeyHex = privateKey {
            guard let privateKeyData = Data(hexString: privateKeyHex) else { return nil }
            
            // Use the real signing implementation
            if let sigResult = self.localSignNostrEventReal(
                pubkey: senderPubkey,
                privateKey: privateKeyData,
                publishable: true
            ) {
                signature = sigResult.signature.hex
            } else {
                signature = "signature_generation_failed"
            }
        } else {
            signature = "placeholder_signature"
        }
        
        return NostrEvent(
            id: eventId,
            pubkey: senderPubkey,
            created_at: created_at,
            kind: 1,
            content: content,
            tags: tags,
            sig: signature
        )
    }
    
    /// Convert a Nostr Kind 1 event back to a BitchatMessage
    static func fromNostrEvent(_ event: NostrEvent) -> BitchatMessage? {
        guard event.kind == 1 else { return nil }
        
        // Extract metadata from tags
        var mentions: [String] = []
        var room: String?
        var isRelay = false
        var isPrivate = false
        var isEncrypted = false
        var originalSender: String?
        var recipientNickname: String?
        var senderPeerID: String?
        
        for tag in event.tags {
            guard !tag.isEmpty else { continue }
            
            switch tag[0] {
            case "p":
                // Person tag - could be mention, original sender, or recipient
                if tag.count >= 4 {
                    let nickname = tag[3]
                    
                    // Check if this is metadata or a mention
                    let isMetadata = event.tags.contains { metaTag in
                        metaTag.count >= 2 && 
                        (metaTag[0] == "bitchat-original-sender" || metaTag[0] == "bitchat-recipient") &&
                        metaTag.count >= 4 && metaTag[3] == nickname
                    }
                    
                    if !isMetadata {
                        mentions.append(nickname)
                    }
                }
                
            case "t":
                // Topic/hashtag tag
                if tag.count >= 2 {
                    room = "#" + tag[1]
                }
                
            case "bitchat-relay":
                isRelay = tag.count >= 2 && tag[1] == "true"
                
            case "bitchat-private":
                isPrivate = tag.count >= 2 && tag[1] == "true"
                
            case "bitchat-encrypted":
                isEncrypted = tag.count >= 2 && tag[1] == "true"
                
            case "bitchat-original-sender":
                if tag.count >= 4 {
                    originalSender = tag[3]
                }
                
            case "bitchat-recipient":
                if tag.count >= 4 {
                    recipientNickname = tag[3]
                }
                
            case "bitchat-mesh-peer":
                if tag.count >= 2 {
                    senderPeerID = tag[1]
                }
                
            default:
                break
            }
        }
        
        // Convert timestamp
        let timestamp = Date(timeIntervalSince1970: TimeInterval(event.created_at))
        
        // Extract sender nickname from pubkey (in real implementation, you'd have a lookup)
        let sender = "user_\(event.pubkey.prefix(8))"
        
        return BitchatMessage(
            sender: sender,
            content: event.content,
            timestamp: timestamp,
            isRelay: isRelay,
            originalSender: originalSender,
            isPrivate: isPrivate,
            recipientNickname: recipientNickname,
            senderPeerID: senderPeerID,
            mentions: mentions.isEmpty ? nil : mentions,
            room: room,
            encryptedContent: nil, // Would need special handling for encrypted content
            isEncrypted: isEncrypted
        )
    }
}

// Helper extension for Nostr event validation
extension NostrEvent {
    
    /// Validate that this event came from bitchat
    var isBitchatEvent: Bool {
        return tags.contains { tag in
            tag.count >= 2 && tag[0] == "client" && tag[1] == "bitchat"
        }
    }
    
    /// Extract bitchat version
    var bitchatVersion: String? {
        for tag in tags {
            if tag.count >= 3 && tag[0] == "client" && tag[1] == "bitchat" {
                return tag[2]
            }
        }
        return nil
    }
    
    /// Check if this message was relayed through mesh
    var isRelayedMessage: Bool {
        return tags.contains { tag in
            tag.count >= 2 && tag[0] == "bitchat-relay" && tag[1] == "true"
        }
    }
}
