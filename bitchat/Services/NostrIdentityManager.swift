//
// NostrIdentityManager.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import CryptoKit
import Combine

/// Manager for automatic Nostr identity integration
/// Automatically fetches user's Nostr profile when nsec is set and updates their username
class NostrIdentityManager: ObservableObject {
    static let shared = NostrIdentityManager()
    
    @Published var currentProfile: NostrProfile?
    @Published var isLoadingProfile = false
    @Published var profileError: String?
    
    private var profileUpdateCancellable: AnyCancellable?
    private let userDefaults = UserDefaults.standard
    private let lastProfileUpdateKey = "NostrIdentityManager.lastProfileUpdate"
    private let cachedProfileKey = "NostrIdentityManager.cachedProfile"
    private let profileRefreshInterval: TimeInterval = 300 // 5 minutes
    
    private init() {
        loadCachedProfile()
        setupProfileUpdates()
    }
    
    /// Check if user has set a Nostr private key and automatically update their profile
    func checkAndUpdateProfile(forceRefresh: Bool = false) async {
        guard let privateKeyHex = NostrSettings.privateKey else {
            currentProfile = nil
            clearCachedProfile()
            return
        }
        
        // Check if we should refresh (every 5 minutes max) - but skip cache check if forceRefresh is true
        if !forceRefresh {
            let lastUpdate = userDefaults.double(forKey: lastProfileUpdateKey)
            let now = Date().timeIntervalSince1970
            
            if currentProfile != nil && (now - lastUpdate) < profileRefreshInterval {
                return
            }
        }
        
        await updateProfileFromPrivateKey(privateKeyHex)
    }
    
    /// Derive public key from private key and fetch profile
    private func updateProfileFromPrivateKey(_ privateKeyHex: String) async {
        guard let privateKeyData = Data(hexString: privateKeyHex) else {
            profileError = "Invalid private key format"
            return
        }
        
        // Derive public key from private key
        let publicKeyHex = derivePublicKey(from: privateKeyData)
        
        await updateProfileFromPublicKey(publicKeyHex)
    }
    
    /// Fetch profile for the given public key
    private func updateProfileFromPublicKey(_ publicKeyHex: String) async {
        await MainActor.run {
            isLoadingProfile = true
            profileError = nil
        }
        
        // Start the profile service if needed
        await NostrProfileManager.shared.start()
        
        // Fetch the profile
        if let profile = await NostrProfileManager.shared.getProfile(for: publicKeyHex) {
            await MainActor.run {
                currentProfile = profile
                isLoadingProfile = false
                cacheProfile(profile)
                recordProfileUpdate()
            }
            
            // Get the current nickname from ChatViewModel to use as fallback
            let currentNickname = await getCurrentBitchatNickname()
            
            // Check if we should update the nickname with Nostr data
            let nostrDisplayName = profile.bestDisplayName
            if let nostrDisplayName = nostrDisplayName, !nostrDisplayName.isEmpty, 
               nostrDisplayName != currentNickname {
                await updateUserNickname(nostrDisplayName)
            }
        } else {
            await MainActor.run {
                profileError = "Profile not found or not published"
                isLoadingProfile = false
            }
            print("[NOSTR] No profile found for public key: \(publicKeyHex.prefix(16))...")
            
            let currentNickname = await getCurrentBitchatNickname()
        }
    }
    
    /// Get the current bitchat nickname for fallback purposes
    private func getCurrentBitchatNickname() async -> String {
        // Since we can't directly access ChatViewModel, we'll use a notification pattern
        // For now, use a reasonable fallback
        return UserDefaults.standard.string(forKey: "bitchat.nickname") ?? "user"
    }
    
    /// Update the user's nickname in ChatViewModel
    @MainActor
    private func updateUserNickname(_ displayName: String) async {
        // We need to find a way to update the ChatViewModel nickname
        // Since we can't directly access it, we'll use NotificationCenter
        NotificationCenter.default.post(
            name: NSNotification.Name("NostrProfileUpdated"),
            object: nil,
            userInfo: ["displayName": displayName, "profile": currentProfile as Any]
        )
    }
    
    /// Derive secp256k1 public key from private key
    private func derivePublicKey(from privateKeyData: Data) -> String {
        // Use the same method as NostrCrypto to ensure consistency
        // TODO: Replace with proper secp256k1 key derivation in production
        guard let publicKeyData = NostrCrypto.derivePublicKey(from: privateKeyData) else {
            fatalError("Failed to derive public key")
        }
        
        return publicKeyData.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Set up automatic profile updates when settings change
    private func setupProfileUpdates() {
        // Monitor for Nostr settings changes
        profileUpdateCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.checkAndUpdateProfile()
                }
            }
    }
    
    /// Cache the profile locally
    private func cacheProfile(_ profile: NostrProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            userDefaults.set(data, forKey: cachedProfileKey)
        }
    }
    
    /// Load cached profile
    private func loadCachedProfile() {
        if let data = userDefaults.data(forKey: cachedProfileKey),
           let profile = try? JSONDecoder().decode(NostrProfile.self, from: data) {
            currentProfile = profile
        }
    }
    
    /// Clear cached profile
    private func clearCachedProfile() {
        userDefaults.removeObject(forKey: cachedProfileKey)
        userDefaults.removeObject(forKey: lastProfileUpdateKey)
    }
    
    /// Record when we last updated the profile
    private func recordProfileUpdate() {
        userDefaults.set(Date().timeIntervalSince1970, forKey: lastProfileUpdateKey)
    }
    
    /// Force refresh the profile
    func forceRefreshProfile() async {
        guard NostrSettings.privateKey != nil else { return }
        clearCachedProfile()
        await checkAndUpdateProfile()
    }
    
    /// Get the current user's Nostr public key
    var currentUserPubkey: String? {
        guard let privateKeyHex = NostrSettings.privateKey,
              let privateKeyData = Data(hexString: privateKeyHex) else {
            return nil
        }
        return derivePublicKey(from: privateKeyData)
    }
    
    /// Check if the user has a Nostr identity configured
    var hasNostrIdentity: Bool {
        return NostrSettings.privateKey != nil
    }
    
    /// Get display name for current user
    var displayName: String? {
        return currentProfile?.bestDisplayName
    }
    
    /// Get short display name for current user
    var shortDisplayName: String? {
        return currentProfile?.shortIdentifier
    }
}



/// Notification names for Nostr identity updates
extension NSNotification.Name {
    static let nostrProfileUpdated = NSNotification.Name("NostrProfileUpdated")
    static let nostrIdentityChanged = NSNotification.Name("NostrIdentityChanged")
}

/// Observable wrapper for easy SwiftUI integration
@MainActor
class NostrIdentityObserver: ObservableObject {
    @Published var profile: NostrProfile?
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasIdentity = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Subscribe to identity manager updates
        NostrIdentityManager.shared.$currentProfile
            .receive(on: DispatchQueue.main)
            .assign(to: &$profile)
        
        NostrIdentityManager.shared.$isLoadingProfile
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)
        
        NostrIdentityManager.shared.$profileError
            .receive(on: DispatchQueue.main)
            .assign(to: &$error)
        
        // Monitor for identity changes
        Publishers.CombineLatest(
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification),
            Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        )
        .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.hasIdentity = NostrIdentityManager.shared.hasNostrIdentity
        }
        .store(in: &cancellables)
        
        // Initial state
        hasIdentity = NostrIdentityManager.shared.hasNostrIdentity
        profile = NostrIdentityManager.shared.currentProfile
    }
    
    func refreshProfile() {
        Task {
            await NostrIdentityManager.shared.forceRefreshProfile()
        }
    }
}
