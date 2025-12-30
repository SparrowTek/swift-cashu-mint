import Fluent
import Foundation

/// Database model for storing blind signature records (NUT-09 restore)
/// Every blind signature issued by the mint is stored here
/// This enables wallet restore functionality - wallets can query which
/// of their blinded messages have been signed
final class BlindSignatureRecord: Model, @unchecked Sendable {
    static let schema = "blind_signatures"
    
    /// Primary key
    @ID(key: .id)
    var id: UUID?
    
    /// Blinded message (B_) as hex string
    /// Indexed for wallet restore lookups
    @Field(key: "b_")
    var B_: String
    
    /// Keyset ID used for signing
    @Field(key: "keyset_id")
    var keysetId: String
    
    /// Amount of the signed token
    @Field(key: "amount")
    var amount: Int
    
    /// Blind signature (C_) as hex string
    @Field(key: "c_")
    var C_: String
    
    /// When this signature was created
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    /// Optional DLEQ proof 'e' value (NUT-12)
    @OptionalField(key: "dleq_e")
    var dleqE: String?
    
    /// Optional DLEQ proof 's' value (NUT-12)
    @OptionalField(key: "dleq_s")
    var dleqS: String?
    
    /// Empty initializer required by Fluent
    init() {}
    
    /// Create a new blind signature record
    init(
        id: UUID? = nil,
        B_: String,
        keysetId: String,
        amount: Int,
        C_: String,
        dleqE: String? = nil,
        dleqS: String? = nil
    ) {
        self.id = id
        self.B_ = B_
        self.keysetId = keysetId
        self.amount = amount
        self.C_ = C_
        self.dleqE = dleqE
        self.dleqS = dleqS
    }
    
    /// Convert to API response format
    func toBlindSignatureData() -> BlindSignatureData {
        var dleq: DLEQProofData? = nil
        if let e = dleqE, let s = dleqS {
            dleq = DLEQProofData(e: e, s: s)
        }
        return BlindSignatureData(
            amount: amount,
            id: keysetId,
            C_: C_,
            dleq: dleq
        )
    }
}

// MARK: - Restore API Models

/// Request for POST /v1/restore (NUT-09)
struct RestoreRequest: Codable, Sendable {
    /// Blinded messages to check for signatures
    let outputs: [BlindedMessageData]
}

/// Response for POST /v1/restore (NUT-09)
struct RestoreResponse: Codable, Sendable {
    /// Blinded messages that have been signed (subset of request)
    let outputs: [BlindedMessageData]
    
    /// Corresponding signatures
    let signatures: [BlindSignatureData]
}
