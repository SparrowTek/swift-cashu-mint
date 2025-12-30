import Fluent
import Foundation

/// Database model for tracking spent proofs (double-spend prevention)
/// The Y value (hash_to_curve(secret)) is used as the unique identifier
/// This is the CRITICAL table for preventing double-spending
final class SpentProof: Model, @unchecked Sendable {
    static let schema = "spent_proofs"
    
    /// Primary key
    @ID(key: .id)
    var id: UUID?
    
    /// Y value: hash_to_curve(secret) as hex string
    /// This MUST have a UNIQUE constraint - it's how we prevent double-spending
    @Field(key: "y")
    var y: String
    
    /// Keyset ID this proof belongs to
    @Field(key: "keyset_id")
    var keysetId: String
    
    /// Amount of this proof in the keyset's unit
    @Field(key: "amount")
    var amount: Int
    
    /// When this proof was spent
    @Timestamp(key: "spent_at", on: .create)
    var spentAt: Date?
    
    /// Witness data for P2PK (NUT-11) or HTLC (NUT-14) proofs
    /// Stores the signature or preimage that authorized spending
    @OptionalField(key: "witness")
    var witness: String?
    
    /// Empty initializer required by Fluent
    init() {}
    
    /// Create a new spent proof record
    init(
        id: UUID? = nil,
        y: String,
        keysetId: String,
        amount: Int,
        witness: String? = nil
    ) {
        self.id = id
        self.y = y
        self.keysetId = keysetId
        self.amount = amount
        self.witness = witness
    }
}

// MARK: - Proof State (NUT-07)

/// Proof state for NUT-07 state check responses
enum ProofState: String, Codable, Sendable {
    /// Proof has not been spent and is not pending
    case unspent = "UNSPENT"
    
    /// Proof is currently being used in an in-flight operation (e.g., melt)
    case pending = "PENDING"
    
    /// Proof has been spent
    case spent = "SPENT"
}

/// Response for a single proof state check (NUT-07)
struct ProofStateResponse: Codable, Sendable {
    /// Y value that was checked
    let y: String
    
    /// Current state of the proof
    let state: ProofState
    
    /// Witness data if the proof was spent with P2PK/HTLC
    let witness: String?
    
    enum CodingKeys: String, CodingKey {
        case y = "Y"
        case state
        case witness
    }
}
