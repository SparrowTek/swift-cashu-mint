import Foundation
import Fluent
import CoreCashu
@preconcurrency import P256K
import CryptoKit

/// Error types for keyset management
enum KeysetManagerError: Error, CustomStringConvertible {
    case keysetNotFound(String)
    case keysetInactive(String)
    case amountNotSupported(Int, String)
    case failedToGenerateKeypair
    case failedToLoadKeyset(String)
    case noActiveKeyset(String)
    
    var description: String {
        switch self {
        case .keysetNotFound(let id):
            return "Keyset not found: \(id)"
        case .keysetInactive(let id):
            return "Keyset is inactive: \(id)"
        case .amountNotSupported(let amount, let keysetId):
            return "Amount \(amount) not supported in keyset \(keysetId)"
        case .failedToGenerateKeypair:
            return "Failed to generate keypair"
        case .failedToLoadKeyset(let reason):
            return "Failed to load keyset: \(reason)"
        case .noActiveKeyset(let unit):
            return "No active keyset found for unit: \(unit)"
        }
    }
}

/// In-memory keyset with decrypted private keys
struct LoadedKeyset: @unchecked Sendable {
    let id: String
    let unit: String
    let active: Bool
    let inputFeePpk: Int
    /// Map of amount to private key
    let privateKeys: [Int: P256K.KeyAgreement.PrivateKey]
    /// Map of amount to public key (hex string for API responses)
    let publicKeys: [Int: String]
}

/// Manages keyset generation, rotation, and storage
/// Uses an actor for thread-safe access to cached keysets
actor KeysetManager {
    private let database: Database
    private var cachedKeysets: [String: LoadedKeyset] = [:]
    private var activeKeysetByUnit: [String: String] = [:]
    
    init(database: Database) {
        self.database = database
    }
    
    // MARK: - Keyset Generation
    
    /// Generate a new keyset for the given unit
    /// Creates keypairs for amounts: 1, 2, 4, 8, ... 2^maxOrder
    func generateKeyset(unit: String, inputFeePpk: Int = 0, maxOrder: Int = 20) async throws -> LoadedKeyset {
        var privateKeys: [Int: P256K.KeyAgreement.PrivateKey] = [:]
        var publicKeys: [Int: String] = [:]
        var storedKeys: [Int: String] = [:]
        
        // Generate keypair for each power-of-2 amount
        for order in 0...maxOrder {
            let amount = 1 << order  // 2^order
            let keypair = try MintKeypair()
            privateKeys[amount] = keypair.privateKey
            publicKeys[amount] = keypair.publicKey.dataRepresentation.hexEncodedString()
            storedKeys[amount] = keypair.privateKey.rawRepresentation.hexEncodedString()
        }
        
        // Derive keyset ID per NUT-02
        let keysetId = deriveKeysetID(from: publicKeys)
        
        // Store in database
        let keysetKeys = KeysetKeys(keys: storedKeys)
        let dbKeyset = MintKeyset(
            keysetId: keysetId,
            unit: unit,
            active: true,
            inputFeePpk: inputFeePpk,
            privateKeys: try keysetKeys.encode()
        )
        try await dbKeyset.save(on: database)
        
        let loadedKeyset = LoadedKeyset(
            id: keysetId,
            unit: unit,
            active: true,
            inputFeePpk: inputFeePpk,
            privateKeys: privateKeys,
            publicKeys: publicKeys
        )
        
        // Cache the keyset
        cachedKeysets[keysetId] = loadedKeyset
        activeKeysetByUnit[unit] = keysetId
        
        return loadedKeyset
    }
    
    // MARK: - Keyset ID Derivation (NUT-02)
    
    /// Derive keyset ID from public keys per NUT-02 specification
    /// Format: "00" + first 7 bytes of SHA256(concatenated sorted public keys) as hex
    private func deriveKeysetID(from publicKeys: [Int: String]) -> String {
        // Sort by amount ascending
        let sortedKeys = publicKeys.sorted { $0.key < $1.key }
        
        // Concatenate all public keys (as raw bytes)
        var concatenated = Data()
        for (_, pubKeyHex) in sortedKeys {
            if let pubKeyData = Data(hexString: pubKeyHex) {
                concatenated.append(pubKeyData)
            }
        }
        
        // SHA256 hash
        let hash = SHA256Helper.hash(data: concatenated)
        
        // Take first 7 bytes and convert to hex
        let truncated = Array(hash.prefix(7))
        let hexString = truncated.map { String(format: "%02x", $0) }.joined()
        
        // Prefix with version "00"
        return "00" + hexString
    }
    
    // MARK: - Keyset Retrieval
    
    /// Get the active keyset for a unit
    func getActiveKeyset(unit: String) async throws -> LoadedKeyset {
        // Check cache first
        if let keysetId = activeKeysetByUnit[unit], let keyset = cachedKeysets[keysetId] {
            return keyset
        }
        
        // Load from database
        guard let dbKeyset = try await MintKeyset.query(on: database)
            .filter(\.$unit == unit)
            .filter(\.$active == true)
            .first() else {
            throw KeysetManagerError.noActiveKeyset(unit)
        }
        
        let loaded = try loadKeyset(dbKeyset)
        cachedKeysets[loaded.id] = loaded
        activeKeysetByUnit[unit] = loaded.id
        return loaded
    }
    
    /// Get a specific keyset by ID
    func getKeyset(id: String) async throws -> LoadedKeyset {
        // Check cache first
        if let keyset = cachedKeysets[id] {
            return keyset
        }
        
        // Load from database
        guard let dbKeyset = try await MintKeyset.query(on: database)
            .filter(\.$keysetId == id)
            .first() else {
            throw KeysetManagerError.keysetNotFound(id)
        }
        
        let loaded = try loadKeyset(dbKeyset)
        cachedKeysets[loaded.id] = loaded
        return loaded
    }
    
    /// Get all keysets (for /v1/keysets endpoint)
    func getAllKeysets() async throws -> [KeysetAPIInfo] {
        let dbKeysets = try await MintKeyset.query(on: database).all()
        return dbKeysets.map { KeysetAPIInfo(from: $0) }
    }
    
    /// Get all active keysets with full keys (for /v1/keys endpoint)
    func getActiveKeysetsWithKeys() async throws -> [LoadedKeyset] {
        let dbKeysets = try await MintKeyset.query(on: database)
            .filter(\.$active == true)
            .all()
        
        var result: [LoadedKeyset] = []
        for dbKeyset in dbKeysets {
            let loaded = try loadKeyset(dbKeyset)
            cachedKeysets[loaded.id] = loaded
            if loaded.active {
                activeKeysetByUnit[loaded.unit] = loaded.id
            }
            result.append(loaded)
        }
        return result
    }
    
    // MARK: - Key Access
    
    /// Get the private key for a specific amount in a keyset
    func getPrivateKey(keysetId: String, amount: Int) async throws -> P256K.KeyAgreement.PrivateKey {
        let keyset = try await getKeyset(id: keysetId)
        
        guard let privateKey = keyset.privateKeys[amount] else {
            throw KeysetManagerError.amountNotSupported(amount, keysetId)
        }
        
        return privateKey
    }
    
    /// Get the public key (hex) for a specific amount in a keyset
    func getPublicKey(keysetId: String, amount: Int) async throws -> String {
        let keyset = try await getKeyset(id: keysetId)
        
        guard let publicKey = keyset.publicKeys[amount] else {
            throw KeysetManagerError.amountNotSupported(amount, keysetId)
        }
        
        return publicKey
    }
    
    // MARK: - Keyset Rotation
    
    /// Deactivate a keyset (for key rotation)
    func deactivateKeyset(id: String) async throws {
        guard let dbKeyset = try await MintKeyset.query(on: database)
            .filter(\.$keysetId == id)
            .first() else {
            throw KeysetManagerError.keysetNotFound(id)
        }
        
        dbKeyset.active = false
        dbKeyset.deactivatedAt = Date()
        try await dbKeyset.save(on: database)
        
        // Update cache
        if var cached = cachedKeysets[id] {
            cached = LoadedKeyset(
                id: cached.id,
                unit: cached.unit,
                active: false,
                inputFeePpk: cached.inputFeePpk,
                privateKeys: cached.privateKeys,
                publicKeys: cached.publicKeys
            )
            cachedKeysets[id] = cached
        }
        
        // Remove from active keyset mapping if it was active
        for (unit, activeId) in activeKeysetByUnit {
            if activeId == id {
                activeKeysetByUnit.removeValue(forKey: unit)
            }
        }
    }
    
    // MARK: - Private Helpers
    
    /// Load a keyset from database model
    private func loadKeyset(_ dbKeyset: MintKeyset) throws -> LoadedKeyset {
        let storedKeys = try KeysetKeys.decode(from: dbKeyset.privateKeys)
        
        var privateKeys: [Int: P256K.KeyAgreement.PrivateKey] = [:]
        var publicKeys: [Int: String] = [:]
        
        for amount in storedKeys.amounts {
            guard let privateKeyHex = storedKeys.privateKey(for: amount),
                  let privateKeyData = Data(hexString: privateKeyHex) else {
                throw KeysetManagerError.failedToLoadKeyset("Invalid private key data for amount \(amount)")
            }
            
            let privateKey = try P256K.KeyAgreement.PrivateKey(dataRepresentation: privateKeyData)
            privateKeys[amount] = privateKey
            publicKeys[amount] = privateKey.publicKey.dataRepresentation.hexEncodedString()
        }
        
        return LoadedKeyset(
            id: dbKeyset.keysetId,
            unit: dbKeyset.unit,
            active: dbKeyset.active,
            inputFeePpk: dbKeyset.inputFeePpk,
            privateKeys: privateKeys,
            publicKeys: publicKeys
        )
    }
    
    // MARK: - Initialization
    
    /// Load all keysets from database into cache on startup
    func loadAllKeysets() async throws {
        let dbKeysets = try await MintKeyset.query(on: database).all()
        
        for dbKeyset in dbKeysets {
            let loaded = try loadKeyset(dbKeyset)
            cachedKeysets[loaded.id] = loaded
            
            if loaded.active {
                activeKeysetByUnit[loaded.unit] = loaded.id
            }
        }
    }
}

// MARK: - Data Extensions

extension Data {
    /// Initialize from hex string
    init?(hexString: String) {
        let hex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        guard hex.count % 2 == 0 else { return nil }
        
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
    
    /// Convert to hex string
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - SHA256 Helper

enum SHA256Helper {
    static func hash(data: Data) -> Data {
        let digest = CryptoKit.SHA256.hash(data: data)
        return Data(digest)
    }
}
