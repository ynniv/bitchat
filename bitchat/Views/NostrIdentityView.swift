//
// NostrIdentityView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// View that displays the user's Nostr identity status and profile information
struct NostrIdentityView: View {
    @StateObject private var identityObserver = NostrIdentityObserver()
    @Environment(\.colorScheme) var colorScheme
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.7) : Color(red: 0, green: 0.5, blue: 0).opacity(0.7)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: identityObserver.hasIdentity ? "person.badge.key.fill" : "person.badge.key")
                    .font(.system(size: 24))
                    .foregroundColor(identityObserver.hasIdentity ? textColor : secondaryTextColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nostr Identity")
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundColor(textColor)
                    
                    Text(identityObserver.hasIdentity ? "Connected" : "Not configured")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                }
                
                Spacer()
                
                if identityObserver.hasIdentity {
                    Button(action: {
                        identityObserver.refreshProfile()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16))
                            .foregroundColor(textColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(identityObserver.isLoading)
                }
            }
            
            // Profile Information
            if identityObserver.hasIdentity {
                if identityObserver.isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading Nostr profile...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                    }
                } else if let profile = identityObserver.profile {
                    ProfileInfoView(profile: profile, textColor: textColor, secondaryTextColor: secondaryTextColor)
                } else if let error = identityObserver.error {
                    ErrorView(error: error, secondaryTextColor: secondaryTextColor)
                } else {
                    NoProfileView(secondaryTextColor: secondaryTextColor)
                }
            } else {
                SetupView(textColor: textColor, secondaryTextColor: secondaryTextColor)
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(textColor.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            if identityObserver.hasIdentity {
                identityObserver.refreshProfile()
            }
        }
    }
}

/// Profile information display
private struct ProfileInfoView: View {
    let profile: NostrProfile
    let textColor: Color
    let secondaryTextColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Display name
            if let displayName = profile.bestDisplayName {
                HStack {
                    Text("Display Name:")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                    
                    Text(displayName)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(textColor)
                }
            }
            
            // NIP-05 verification
            if let nip05 = profile.nip05 {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    
                    Text("Verified:")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                    
                    Text(nip05)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green)
                }
            }
            
            // Profile picture indicator
            if profile.picture != nil {
                HStack {
                    Image(systemName: "photo.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                    
                    Text("Profile picture available")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                }
            }
            
            // Bio preview
            if let about = profile.about, !about.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bio:")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                    
                    Text(about.prefix(100) + (about.count > 100 ? "..." : ""))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(textColor)
                        .lineLimit(3)
                }
            }
            
            // Additional info
            HStack {
                Image(systemName: "clock.fill")
                    .font(.system(size: 10))
                    .foregroundColor(secondaryTextColor)
                
                Text("Profile updated from Nostr network")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
            }
        }
    }
}

/// Error display
private struct ErrorView: View {
    let error: String
    let secondaryTextColor: Color
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            
            Text(error)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(secondaryTextColor)
        }
    }
}

/// No profile found display
private struct NoProfileView: View {
    let secondaryTextColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Profile not found on Nostr network")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(secondaryTextColor)
            
            Text("Consider publishing your profile to Nostr relays")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(secondaryTextColor)
        }
    }
}

/// Setup instructions
private struct SetupView: View {
    let textColor: Color
    let secondaryTextColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set up your Nostr identity to:")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(textColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("• Use your Nostr display name as username")
                Text("• Show your profile picture in messages")
                Text("• Display verification badges")
                Text("• Connect with the Nostr ecosystem")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(secondaryTextColor)
            
            Text("Configure your private key in Nostr Settings")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(secondaryTextColor)
                .italic()
        }
    }
}

/// Compact version for use in smaller spaces
struct CompactNostrIdentityView: View {
    @StateObject private var identityObserver = NostrIdentityObserver()
    @Environment(\.colorScheme) var colorScheme
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.7) : Color(red: 0, green: 0.5, blue: 0).opacity(0.7)
    }
    
    var body: some View {
        HStack {
            Image(systemName: identityObserver.hasIdentity ? "person.badge.key.fill" : "person.badge.key")
                .font(.system(size: 16))
                .foregroundColor(identityObserver.hasIdentity ? textColor : secondaryTextColor)
            
            VStack(alignment: .leading, spacing: 2) {
                if let profile = identityObserver.profile, let displayName = profile.bestDisplayName {
                    Text(displayName)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(textColor)
                    
                    if let nip05 = profile.nip05 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.green)
                            
                            Text(nip05)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.green)
                        }
                    }
                } else if identityObserver.hasIdentity {
                    if identityObserver.isLoading {
                        Text("Loading...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                    } else {
                        Text("Profile not found")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                    }
                } else {
                    Text("Nostr not configured")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                }
            }
            
            Spacer()
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        NostrIdentityView()
        
        Divider()
        
        CompactNostrIdentityView()
    }
    .padding()
}
