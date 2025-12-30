import Fluent
import Foundation

/// Database model for tracking pending (in-flight) proofs (NUT-07)
/// Proofs are marked as pending when they are being used in an operation
/// that hasn't completed yet (e.g., a melt operation waiting for Lightning payment)
final class PendingProof: Model, @unchecked Sendable {
    static let schema = "pending_proofs"
    
    /// Primary key
    @ID(key: .id)
    var id: UUID?
    
    /// Y value: hash_to_curve(secret) as hex string
    /// Must be unique - a proof can only be pending in one operation
    @Field(key: "y")
    var y: String
    
    /// Keyset ID this proof belongs to
    @Field(key: "keyset_id")
    var keysetId: String
    
    /// Amount of this proof
    @Field(key: "amount")
    var amount: Int
    
    /// Quote ID this proof is associated with (for melt operations)
    @OptionalField(key: "quote_id")
    var quoteId: String?
    
    /// When this proof was marked as pending
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    /// When this pending status expires
    /// After this time, the proof can be reclaimed if the operation failed
    @Field(key: "expires_at")
    var expiresAt: Date
    
    /// Empty initializer required by Fluent
    init() {}
    
    /// Create a new pending proof record
    init(
        id: UUID? = nil,
        y: String,
        keysetId: String,
        amount: Int,
        quoteId: String? = nil,
        expiresAt: Date
    ) {
        self.id = id
        self.y = y
        self.keysetId = keysetId
        self.amount = amount
        self.quoteId = quoteId
        self.expiresAt = expiresAt
    }
}

// MARK: - Check State API Models

/// Request for POST /v1/checkstate (NUT-07)
struct CheckStateRequest: Codable, Sendable {
    /// Y values to check (hash_to_curve(secret) for each proof)
    let Ys: [String]
    
    enum CodingKeys: String, CodingKey {
        case Ys
    }
}

/// Response for POST /v1/checkstate (NUT-07)
struct CheckStateResponse: Codable, Sendable {
    /// States for each Y value (in same order as request)
    let states: [ProofStateResponse]
}
