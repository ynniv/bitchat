//
// NostrSettingsView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
import CryptoKit

struct NostrSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var isEnabled = NostrSettings.isEnabled
    @State private var privateKey = ""
    @State private var relayURL = NostrSettings.relayURL
    @State private var publishToRelays = NostrSettings.publishToRelays
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .center, spacing: 8) {
                        Image(systemName: "person.badge.key")
                            .font(.system(size: 48))
                            .foregroundColor(textColor)
                        
                        Text("Nostr Bridge Settings")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(textColor)
                        
                        Text("Configure Nostr relay integration")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                    
                    // Enable Toggle
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader("Bridge Configuration")
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $isEnabled) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Enable Nostr Bridge")
                                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                        .foregroundColor(textColor)
                                    
                                    Text("Publish mesh messages to Nostr relays")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(secondaryTextColor)
                                }
                            }
                            .toggleStyle(SwitchToggleStyle(tint: textColor))
                        }
                    }
                    
                    if isEnabled {
                        // Identity Settings
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader("Nostr Identity")
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Private Key (hex)")
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(textColor)
                                
                                TextField("Enter 64-character hex private key (leave blank for random)", text: $privateKey)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.system(size: 12, design: .monospaced))
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                
                                Text("Leave blank to generate a new random key")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(secondaryTextColor)
                                
                                Button(action: generateNewKey) {
                                    Text("Generate New Key")
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundColor(backgroundColor)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(textColor)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        // Relay Settings
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader("Relay Configuration")
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Relay URL")
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(textColor)
                                
                                TextField("wss://relay.example.com", text: $relayURL)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.system(size: 12, design: .monospaced))
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                
                                // Show list of default relays
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Default relays available:")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(secondaryTextColor)
                                    
                                    ForEach(NostrSettings.defaultRelayURLs, id: \.self) { relay in
                                        Button(action: { relayURL = relay }) {
                                            Text("• \(relay)")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(textColor)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Button(action: { NostrSettings.resetRelayURLsToDefaults() }) {
                                        Text("Reset to all defaults")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(textColor)
                                            .underline()
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                Toggle(isOn: $publishToRelays) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Publish to Relays")
                                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                            .foregroundColor(textColor)
                                        
                                        Text("Send messages to Nostr relays (disable for identity-only mode)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(secondaryTextColor)
                                    }
                                }
                                .toggleStyle(SwitchToggleStyle(tint: textColor))
                            }
                        }
                        
                        // How it Works
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader("How It Works")
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• All messages use dual signatures (bitchat + Nostr)")
                                Text("• Messages appear in both mesh and Nostr networks")
                                Text("• Your bitchat identity remains separate from Nostr")
                                Text("• Disable relay publishing for identity-only mode")
                                Text("• Private keys stored securely in Keychain")
                                Text("• Compatible with standard Nostr clients")
                            }
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(textColor)
                        }
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        if isEnabled {
                            Button(action: saveSettings) {
                                Text("Save Settings")
                                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                    .foregroundColor(backgroundColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(textColor)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Button(action: { dismiss() }) {
                            Text(isEnabled ? "Cancel" : "Close")
                                .font(.system(size: 16, design: .monospaced))
                                .foregroundColor(textColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(textColor, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top)
                }
                .padding()
            }
            .background(backgroundColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(textColor)
                }
            }
        }
        .alert("Settings", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func generateNewKey() {
        let keyData = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        privateKey = keyData.map { String(format: "%02x", $0) }.joined()
    }
    
    private func saveSettings() {
        // Validate private key if provided
        if !privateKey.isEmpty {
            guard privateKey.count == 64,
                  privateKey.allSatisfy({ $0.isHexDigit }) else {
                alertMessage = "Private key must be exactly 64 hexadecimal characters"
                showAlert = true
                return
            }
        }
        
        // Validate relay URL
        guard relayURL.hasPrefix("wss://") || relayURL.hasPrefix("ws://") else {
            alertMessage = "Relay URL must start with wss:// or ws://"
            showAlert = true
            return
        }
        
        // Save settings using NostrSettings
        UserDefaults.standard.set(isEnabled, forKey: "NostrBridgeEnabled")
        NostrSettings.setRelayURL(relayURL)
        UserDefaults.standard.set(publishToRelays, forKey: "NostrPublishToRelays")
        
        // Save private key to Keychain if provided
        if !privateKey.isEmpty {
            savePrivateKeyToKeychain(privateKey)
            
            // Trigger automatic profile lookup when private key is set
            Task {
                await NostrIdentityManager.shared.checkAndUpdateProfile()
            }
        }
        
        alertMessage = "Settings saved successfully! Nostr bridge is now configured."
        showAlert = true
    }
    
    private func savePrivateKeyToKeychain(_ key: String) {
        let keyData = key.data(using: .utf8)!
        
        // Delete existing key first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "NostrPrivateKey",
            kSecAttrService as String: "bitchat"
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new key
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "NostrPrivateKey",
            kSecAttrService as String: "bitchat",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}

struct SectionHeader: View {
    let title: String
    @Environment(\.colorScheme) var colorScheme
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    init(_ title: String) {
        self.title = title
    }
    
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 16, weight: .bold, design: .monospaced))
            .foregroundColor(textColor)
            .padding(.top, 8)
    }
}

#Preview {
    NostrSettingsView()
}
