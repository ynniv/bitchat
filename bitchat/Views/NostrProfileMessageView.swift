//
// NostrProfileMessageView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// A message view that shows Nostr profile information for dual-signed messages
struct NostrProfileMessageView: View {
    let message: BitchatMessage
    @State private var displayName: String?
    @State private var nostrProfile: NostrProfile?
    @State private var isLoading = false
    
    var body: some View {
        HStack {
            // Profile picture (if available)
            AsyncImage(url: profilePictureURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .overlay(
                        Text(profileInitials)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    )
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    // Display name with loading state
                    if isLoading {
                        Text(message.sender)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Text(effectiveDisplayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if message.hasDualSignature {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                    }
                    
                    Spacer()
                    
                    Text(formatTimestamp(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Message content
                Text(message.content)
                    .font(.body)
                
                // Nostr verification info (if dual-signed)
                if message.hasDualSignature, let profile = nostrProfile {
                    HStack {
                        Image(systemName: "person.badge.key.fill")
                            .foregroundColor(.green)
                            .font(.caption2)
                        
                        if let nip05 = profile.nip05 {
                            Text("@\(nip05)")
                                .font(.caption2)
                                .foregroundColor(.green)
                        } else {
                            Text("Verified Nostr")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
        }
        .task {
            await loadNostrProfile()
        }
        .onChange(of: message.id) { _ in
            Task {
                await loadNostrProfile()
            }
        }
    }
    
    private var effectiveDisplayName: String {
        if let displayName = displayName {
            return displayName
        }
        return message.sender
    }
    
    private var profilePictureURL: URL? {
        guard let pictureString = nostrProfile?.picture,
              let url = URL(string: pictureString) else {
            return nil
        }
        return url
    }
    
    private var profileInitials: String {
        if let displayName = displayName {
            return String(displayName.prefix(2)).uppercased()
        }
        return String(message.sender.prefix(2)).uppercased()
    }
    
    @MainActor
    private func loadNostrProfile() async {
        guard message.hasDualSignature else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        // Start the profile service if needed
        await NostrProfileManager.shared.start()
        
        // Load display name and profile
        async let displayNameTask = message.getNostrDisplayName()
        async let profileTask = message.getNostrProfile()
        
        let (loadedDisplayName, loadedProfile) = await (displayNameTask, profileTask)
        
        if let loadedDisplayName = loadedDisplayName {
            displayName = loadedDisplayName
        }
        
        if let loadedProfile = loadedProfile {
            nostrProfile = loadedProfile
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "now"
        } else if timeInterval < 3600 {
            return "\(Int(timeInterval / 60))m"
        } else if timeInterval < 86400 {
            return "\(Int(timeInterval / 3600))h"
        } else {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

/// A compact version for use in lists
struct CompactNostrMessageView: View {
    let message: BitchatMessage
    @State private var displayName: String?
    @State private var isLoading = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text(message.sender)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(effectiveDisplayName)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    if message.hasDualSignature {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 10))
                    }
                    
                    Spacer()
                    
                    Text(formatTimestamp(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Text(message.content)
                    .font(.body)
                    .lineLimit(3)
            }
        }
        .task {
            await loadDisplayName()
        }
    }
    
    private var effectiveDisplayName: String {
        if let displayName = displayName {
            return displayName
        }
        return message.sender
    }
    
    @MainActor
    private func loadDisplayName() async {
        guard message.hasDualSignature else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        await NostrProfileManager.shared.start()
        
        if let loadedDisplayName = await message.getNostrShortDisplayName() {
            displayName = loadedDisplayName
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "now"
        } else if timeInterval < 3600 {
            return "\(Int(timeInterval / 60))m"
        } else {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
    }
}

#Preview {
    let sampleMessage = BitchatMessage(
        sender: "alice",
        content: "Hello from the Nostr network!",
        timestamp: Date(),
        isRelay: false,
        dualSignature: DualSignatureInfo(
            nostrPubkey: "npub1234567890abcdef",
            nostrSignature: Data(),
            bridgeOptions: .publishable
        )
    )
    
    VStack {
        NostrProfileMessageView(message: sampleMessage)
            .padding()
        
        Divider()
        
        CompactNostrMessageView(message: sampleMessage)
            .padding()
    }
}
