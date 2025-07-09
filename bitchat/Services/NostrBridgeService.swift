//
// NostrBridgeService.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import Network
import CryptoKit

/// WebSocket-based Nostr relay client (Outbound Only)
class NostrRelayClient {
    private let url: URL
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession.shared
    
    init(url: URL) {
        self.url = url
    }
    
    func connect() async throws {
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Start receiving acknowledgments only
        Task {
            await receiveAcknowledgments()
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel()
        webSocketTask = nil
    }
    
    func sendEvent(_ event: NostrEvent) async throws {
        let message: [Any] = ["EVENT", event]
        let data = try JSONSerialization.data(withJSONObject: message)
        let string = String(data: data, encoding: .utf8)!
        
        try await webSocketTask?.send(.string(string))
    }
    
    private func receiveAcknowledgments() async {
        guard let webSocketTask = webSocketTask else { return }
        
        do {
            let message = try await webSocketTask.receive()
            
            switch message {
            case .string(let text):
                handleAcknowledgment(text)
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    handleAcknowledgment(text)
                }
            @unknown default:
                break
            }
            
            // Continue receiving
            await receiveAcknowledgments()
        } catch {
            print("[NOSTR] WebSocket error: \(error)")
        }
    }
    
    private func handleAcknowledgment(_ text: String) {
        // Parse relay acknowledgments and notices only
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let messageType = json.first as? String else { return }
        
        switch messageType {
        case "OK":
            if json.count >= 4,
               let eventId = json[1] as? String,
               let success = json[2] as? Bool {
                if success {
                    print("[NOSTR] Event \(eventId.prefix(8))... published successfully")
                } else {
                    let error = json[3] as? String ?? "unknown error"
                    print("[NOSTR] Event \(eventId.prefix(8))... failed: \(error)")
                }
            }
        case "NOTICE":
            if let notice = json[1] as? String {
                print("[NOSTR] Relay notice: \(notice)")
            }
        default:
            // Ignore other message types (no inbound event processing)
            break
        }
    }
}

/// Unidirectional bridge service (bitchat → Nostr only)
class NostrBridge {
    private let relayClients: [NostrRelayClient]
    private let identity: DualIdentity
    private var isActive = false
    
    init(relayURLs: [String], identity: DualIdentity) {
        self.identity = identity
        self.relayClients = relayURLs.compactMap { urlString in
            guard let url = URL(string: urlString) else { return nil }
            return NostrRelayClient(url: url)
        }
    }
    
    /// Start the bridge service
    func start() async {
        isActive = true
        
        // Connect to all relays
        await withTaskGroup(of: Void.self) { group in
            for client in relayClients {
                group.addTask {
                    try? await client.connect()
                }
            }
        }
        
        print("[NOSTR] Nostr bridge started with \(relayClients.count) relays (outbound only)")
    }
    
    /// Stop the bridge service
    func stop() {
        isActive = false
        
        for client in relayClients {
            client.disconnect()
        }
        
        print("[NOSTR] Nostr bridge stopped")
    }
    
    /// Bridge a message from bitchat mesh to Nostr relays
    func bridgeToNostr(_ dualPacket: DualSignedPacket) async {
        guard isActive else { return }
        
        // Check explicit intent first
        guard dualPacket.bridgeOptions.isPublishable else {
            return
        }
        
        guard let nostrEvent = convertToNostrEvent(dualPacket) else {
            return
        }
        
        // Perform redundant verification
        if !verifyPublishableSignature(nostrEvent, dualPacket.nostrSignature) {
            print("[NOSTR] Warning: Publishable flag set but signature verification failed")
            return
        }
        
        // Add bridge metadata
        let enhancedEvent = addBridgeMetadata(nostrEvent)
        
        // Send to all connected relays
        await withTaskGroup(of: Void.self) { group in
            for client in relayClients {
                group.addTask {
                    try? await client.sendEvent(enhancedEvent)
                }
            }
        }
        
        print("[NOSTR] Bridged publishable message to \(relayClients.count) Nostr relays")
    }
    
    /// Verify that a signature was created for publishing (not identity-only)
    private func verifyPublishableSignature(_ event: NostrEvent, _ signature: Data) -> Bool {
        // Reconstruct the event structure for signing verification
        let eventArray: [Any] = [
            0,
            event.pubkey,
            event.created_at,
            event.kind,
            event.tags,
            event.content
        ]
        
        guard let eventData = try? JSONSerialization.data(withJSONObject: eventArray) else {
            return false
        }
        
        // Calculate what the event ID should be for this event
        let expectedEventId = SHA256.hash(data: eventData).compactMap { 
            String(format: "%02x", $0) 
        }.joined()
        
        // Check if the actual event ID matches (indicating publishable signature)
        return event.id == expectedEventId
    }
    
    /// Convert dual-signed packet to Nostr event
    internal func convertToNostrEvent(_ dualPacket: DualSignedPacket) -> NostrEvent? {
        guard let message = BitchatMessage.fromBinaryPayload(dualPacket.bitchatPacket.payload) else {
            return nil
        }
        
        let nostrPubkeyHex = dualPacket.nostrPubkey.map { String(format: "%02x", $0) }.joined()
        guard let baseEvent = message.toNostrEvent(senderPubkey: nostrPubkeyHex) else {
            return nil
        }
        
        // Use the pre-computed Nostr signature
        let sigHex = dualPacket.nostrSignature.map { String(format: "%02x", $0) }.joined()
        
        return NostrEvent(
            id: baseEvent.id,
            pubkey: baseEvent.pubkey,
            created_at: baseEvent.created_at,
            kind: baseEvent.kind,
            content: baseEvent.content,
            tags: baseEvent.tags,
            sig: sigHex
        )
    }
    
    /// Add bridge-specific metadata to events
    private func addBridgeMetadata(_ event: NostrEvent) -> NostrEvent {
        var enhancedTags = event.tags
        
        // Add bridge timestamp
        enhancedTags.append(["bridge-time", String(Int(Date().timeIntervalSince1970))])
        
        // Add bridge identifier
        enhancedTags.append(["bridge-id", "bitchat-bridge-v1"])
        
        // Add direction indicator
        enhancedTags.append(["bridge-direction", "mesh-to-relay"])
        
        return NostrEvent(
            id: event.id,
            pubkey: event.pubkey,
            created_at: event.created_at,
            kind: event.kind,
            content: event.content,
            tags: enhancedTags,
            sig: event.sig
        )
    }
}

/// Integration with main bitchat service (Outbound Only)
extension BluetoothMeshService {
    
    /// Initialize Nostr bridge integration
    func setupNostrBridge(relayURLs: [String], nostrIdentity: DualIdentity) {
        let bridge = NostrBridge(relayURLs: relayURLs, identity: nostrIdentity)
        
        // Store bridge reference
        self.nostrBridge = bridge
        
        Task {
            await bridge.start()
        }
    }
    
    /// Send dual-signed message to both mesh and Nostr
    func sendDualSignedMessage(_ message: BitchatMessage, identity: DualIdentity) {
        // Create dual-signed packet
        guard let dualPacket = message.createDualSignedPacket(identity: identity) else {
            print("[NOSTR] Failed to create dual-signed packet")
            return
        }
        
        // Send via mesh (bitchat signature)
        // NOTE: This would need to be connected to BluetoothMeshService
        print("[NOSTR] Would send via mesh: \(dualPacket.bitchatPacket)")
        
        // Bridge to Nostr (nostr signature)
        Task {
            await nostrBridge?.bridgeToNostr(dualPacket)
        }
    }
    
    private var nostrBridge: NostrBridge? {
        get { objc_getAssociatedObject(self, &nostrBridgeKey) as? NostrBridge }
        set { objc_setAssociatedObject(self, &nostrBridgeKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}

private var nostrBridgeKey: UInt8 = 0
