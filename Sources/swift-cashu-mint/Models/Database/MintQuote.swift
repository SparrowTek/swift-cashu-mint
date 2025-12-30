import Fluent
import Foundation

/// State of a mint quote (NUT-04)
enum MintQuoteState: String, Codable, Sendable {
    /// Invoice has not been paid yet
    case unpaid = "UNPAID"
    
    /// Invoice has been paid, tokens can be minted
    case paid = "PAID"
    
    /// Tokens have been issued for this quote
    case issued = "ISSUED"
}

/// Database model for mint quotes (NUT-04)
/// A mint quote represents a request to mint tokens in exchange for a Lightning payment
final class MintQuote: Model, @unchecked Sendable {
    static let schema = "mint_quotes"
    
    /// Primary key
    @ID(key: .id)
    var id: UUID?
    
    /// Unique quote identifier (random string shown to clients)
    @Field(key: "quote_id")
    var quoteId: String
    
    /// Payment method (e.g., "bolt11")
    @Field(key: "method")
    var method: String
    
    /// Unit for the tokens to be minted
    @Field(key: "unit")
    var unit: String
    
    /// Amount to be minted (in the unit's smallest denomination)
    @Field(key: "amount")
    var amount: Int
    
    /// The Lightning invoice (bolt11 string) to be paid
    @Field(key: "request")
    var request: String
    
    /// Payment hash of the Lightning invoice (for tracking payment)
    @Field(key: "payment_hash")
    var paymentHash: String
    
    /// Current state of the quote
    @Field(key: "state")
    var state: MintQuoteState
    
    /// When the quote/invoice expires
    @Field(key: "expiry")
    var expiry: Date
    
    /// When the quote was created
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    /// When tokens were issued (if state == ISSUED)
    @OptionalField(key: "issued_at")
    var issuedAt: Date?
    
    /// Optional description for the invoice
    @OptionalField(key: "description")
    var invoiceDescription: String?
    
    /// Empty initializer required by Fluent
    init() {}
    
    /// Create a new mint quote
    init(
        id: UUID? = nil,
        quoteId: String,
        method: String = "bolt11",
        unit: String,
        amount: Int,
        request: String,
        paymentHash: String,
        state: MintQuoteState = .unpaid,
        expiry: Date,
        invoiceDescription: String? = nil
    ) {
        self.id = id
        self.quoteId = quoteId
        self.method = method
        self.unit = unit
        self.amount = amount
        self.request = request
        self.paymentHash = paymentHash
        self.state = state
        self.expiry = expiry
        self.invoiceDescription = invoiceDescription
    }
}

// MARK: - API Response Models

/// Response for POST /v1/mint/quote/bolt11 (NUT-04)
struct MintQuoteResponse: Codable, Sendable {
    /// Quote identifier
    let quote: String
    
    /// Lightning invoice to pay
    let request: String
    
    /// Amount that will be minted
    let amount: Int
    
    /// Unit of the tokens
    let unit: String
    
    /// Current state
    let state: MintQuoteState
    
    /// Expiry timestamp (Unix seconds)
    let expiry: Int
    
    init(from quote: MintQuote) {
        self.quote = quote.quoteId
        self.request = quote.request
        self.amount = quote.amount
        self.unit = quote.unit
        self.state = quote.state
        self.expiry = Int(quote.expiry.timeIntervalSince1970)
    }
}

/// Request for POST /v1/mint/quote/bolt11 (NUT-04)
struct MintQuoteRequest: Codable, Sendable {
    /// Amount to mint
    let amount: Int
    
    /// Unit for the tokens
    let unit: String
    
    /// Optional description for the invoice
    let description: String?
    
    init(amount: Int, unit: String, description: String? = nil) {
        self.amount = amount
        self.unit = unit
        self.description = description
    }
}

/// Request for POST /v1/mint/bolt11 (NUT-04)
struct MintRequest: Codable, Sendable {
    /// Quote ID to mint tokens for
    let quote: String
    
    /// Blinded messages to sign
    let outputs: [BlindedMessageData]
}

/// Response for POST /v1/mint/bolt11 (NUT-04)
struct MintResponse: Codable, Sendable {
    /// Blind signatures for the outputs
    let signatures: [BlindSignatureData]
}

// MARK: - Blinded Message/Signature Data

/// Blinded message from client (NUT-00)
struct BlindedMessageData: Codable, Sendable {
    /// Amount for this output
    let amount: Int
    
    /// Keyset ID to use for signing
    let id: String
    
    /// Blinded secret (B_) as hex
    let B_: String
    
    /// Optional witness for spending conditions
    let witness: String?
    
    enum CodingKeys: String, CodingKey {
        case amount, id
        case B_ = "B_"
        case witness
    }
}

/// Blind signature from mint (NUT-00)
struct BlindSignatureData: Codable, Sendable {
    /// Amount of the signed token
    let amount: Int
    
    /// Keyset ID used for signing
    let id: String
    
    /// Blind signature (C_) as hex
    let C_: String
    
    /// Optional DLEQ proof (NUT-12)
    let dleq: DLEQProofData?
    
    enum CodingKeys: String, CodingKey {
        case amount, id
        case C_ = "C_"
        case dleq
    }
}

/// DLEQ proof data (NUT-12)
struct DLEQProofData: Codable, Sendable {
    let e: String
    let s: String
}
