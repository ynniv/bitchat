//
// QuickBridgeTest.swift
// bitchat
//
// Simple test to verify the bridge functionality
//

import Foundation
import CryptoKit

/// Quick test to verify bridge functionality works
class QuickBridgeTest {
    
    static func runTest() {
        print("🚀 Quick Bridge Test")
        print("===================")
        
        // 1. Create identity
        let identity = DualIdentity(useStaticNostr: true)
        print("✅ Identity created")
        print("   Nostr pubkey: \(identity.nostrPublicKeyHex.prefix(16))...")
        
        // 2. Create message  
        let message = BitchatMessage(
            sender: "alice",
            content: "Hello from bitchat!",
            timestamp: Date(),
            isRelay: false,
            room: "#test"
        )
        print("✅ Message created: \"\(message.content)\"")
        
        // 3. Create dual-signed packet
        guard let packet = message.createDualSignedPacket(
            identity: identity,
            bridgeOptions: BridgeOptions.publishable
        ) else {
            print("❌ Failed to create dual-signed packet")
            return
        }
        
        print("✅ Dual-signed packet created")
        print("   Bridge options: publishable=\(packet.bridgeOptions.isPublishable)")
        print("   Bitchat signature: \(packet.bitchatPacket.signature?.count ?? 0) bytes")
        print("   Nostr signature: \(packet.nostrSignature.count) bytes")
        
        // 4. Convert to Nostr event
        let bridge = NostrBridge(relayURLs: [], identity: identity)
        guard let nostrEvent = bridge.convertToNostrEvent(packet) else {
            print("❌ Failed to convert to Nostr event")
            return
        }
        
        print("✅ Converted to Nostr event")
        print("   Event ID: \(nostrEvent.id.prefix(16))...")
        print("   Content: \"\(nostrEvent.content)\"")
        print("   Tags: \(nostrEvent.tags.count)")
        
        print("\n🎉 Bridge test completed successfully!")
        print("   The bitchat-nostr bridge is working correctly.")
    }
}

// Extension to fix method signature for testing
extension BitchatMessage {
    init(sender: String, content: String, timestamp: Date, room: String? = nil) {
        self.init(
            sender: sender,
            content: content,
            timestamp: timestamp,
            isRelay: false,
            room: room
        )
    }
}
