import Fluent
import Foundation

/// Database model for storing mint keysets
/// Each keyset contains private keys for signing tokens of various denominations
final class MintKeyset: Model, @unchecked Sendable {
    static let schema = "mint_keysets"
    
    /// Primary key
    @ID(key: .id)
    var id: UUID?
    
    /// Keyset ID (hex string, derived per NUT-02)
    /// Format: "00" + first 7 bytes of SHA256(concatenated public keys) as hex
    @Field(key: "keyset_id")
    var keysetId: String
    
    /// Unit for this keyset (e.g., "sat", "usd")
    @Field(key: "unit")
    var unit: String
    
    /// Whether this keyset is currently active for signing new tokens
    @Field(key: "active")
    var active: Bool
    
    /// Input fee in parts per thousand (ppk)
    /// Fee = ceil(sum(input_fee_ppk) / 1000)
    @Field(key: "input_fee_ppk")
    var inputFeePpk: Int
    
    /// When this keyset was created
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    /// When this keyset was deactivated (nil if still active)
    @OptionalField(key: "deactivated_at")
    var deactivatedAt: Date?
    
    /// Encrypted private keys JSON: {"amount": "private_key_hex", ...}
    /// Private keys should be encrypted at rest in production
    @Field(key: "private_keys")
    var privateKeys: Data
    
    /// Empty initializer required by Fluent
    init() {}
    
    /// Create a new keyset
    init(
        id: UUID? = nil,
        keysetId: String,
        unit: String,
        active: Bool = true,
        inputFeePpk: Int = 0,
        privateKeys: Data
    ) {
        self.id = id
        self.keysetId = keysetId
        self.unit = unit
        self.active = active
        self.inputFeePpk = inputFeePpk
        self.privateKeys = privateKeys
    }
}

// MARK: - Keyset Key Storage

/// Structure for storing keyset keys (amount -> private key hex)
struct KeysetKeys: Codable, Sendable {
    /// Map of amount to private key (hex encoded)
    let keys: [String: String]
    
    init(keys: [Int: String]) {
        // Convert Int keys to String for JSON encoding
        self.keys = Dictionary(uniqueKeysWithValues: keys.map { (String($0.key), $0.value) })
    }
    
    /// Get the private key for a specific amount
    func privateKey(for amount: Int) -> String? {
        keys[String(amount)]
    }
    
    /// Get all amounts in this keyset
    var amounts: [Int] {
        keys.keys.compactMap { Int($0) }.sorted()
    }
    
    /// Encode to Data for storage
    func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }
    
    /// Decode from stored Data
    static func decode(from data: Data) throws -> KeysetKeys {
        try JSONDecoder().decode(KeysetKeys.self, from: data)
    }
}

// MARK: - Keyset Info (API Response)

/// Keyset information for API responses (NUT-02)
struct KeysetAPIInfo: Codable, Sendable {
    let id: String
    let unit: String
    let active: Bool
    let inputFeePpk: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, unit, active
        case inputFeePpk = "input_fee_ppk"
    }
    
    init(from keyset: MintKeyset) {
        self.id = keyset.keysetId
        self.unit = keyset.unit
        self.active = keyset.active
        self.inputFeePpk = keyset.inputFeePpk > 0 ? keyset.inputFeePpk : nil
    }
}
