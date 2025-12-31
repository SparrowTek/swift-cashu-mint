import Fluent
import Foundation

/// State of a melt quote (NUT-05)
enum MeltQuoteState: String, Codable, Sendable {
    /// Quote created, waiting for proofs to melt
    case unpaid = "UNPAID"
    
    /// Lightning payment is in progress
    case pending = "PENDING"
    
    /// Lightning payment succeeded, tokens melted
    case paid = "PAID"
}

/// Database model for melt quotes (NUT-05)
/// A melt quote represents a request to melt tokens in exchange for a Lightning payment
final class MeltQuote: Model, @unchecked Sendable {
    static let schema = "melt_quotes"
    
    /// Primary key
    @ID(key: .id)
    var id: UUID?
    
    /// Unique quote identifier (random string shown to clients)
    @Field(key: "quote_id")
    var quoteId: String
    
    /// Payment method (e.g., "bolt11")
    @Field(key: "method")
    var method: String
    
    /// Unit of the tokens being melted
    @Field(key: "unit")
    var unit: String
    
    /// The Lightning invoice to pay
    @Field(key: "request")
    var request: String
    
    /// Amount to pay (from the invoice, in the unit's smallest denomination)
    @Field(key: "amount")
    var amount: Int
    
    /// Fee reserve - maximum fee the mint will charge for routing
    /// Client must provide proofs worth at least (amount + feeReserve)
    @Field(key: "fee_reserve")
    var feeReserve: Int
    
    /// Current state of the quote
    @Field(key: "state")
    var state: MeltQuoteState
    
    /// Payment preimage (proof of payment, available when state == PAID)
    @OptionalField(key: "payment_preimage")
    var paymentPreimage: String?
    
    /// Actual fee paid for the Lightning payment (available when state == PAID)
    /// This will be <= feeReserve
    @OptionalField(key: "fee_paid")
    var feePaid: Int?
    
    /// When the quote expires
    @Field(key: "expiry")
    var expiry: Date
    
    /// When the quote was created
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    /// When the payment completed (if state == PAID)
    @OptionalField(key: "paid_at")
    var paidAt: Date?

    /// MPP partial amount in millisats (NUT-15)
    /// If set, this quote is for a partial payment of the invoice
    @OptionalField(key: "mpp_amount")
    var mppAmount: Int?

    /// Empty initializer required by Fluent
    init() {}
    
    /// Create a new melt quote
    init(
        id: UUID? = nil,
        quoteId: String,
        method: String = "bolt11",
        unit: String,
        request: String,
        amount: Int,
        feeReserve: Int,
        state: MeltQuoteState = .unpaid,
        expiry: Date,
        mppAmount: Int? = nil
    ) {
        self.id = id
        self.quoteId = quoteId
        self.method = method
        self.unit = unit
        self.request = request
        self.amount = amount
        self.feeReserve = feeReserve
        self.state = state
        self.expiry = expiry
        self.mppAmount = mppAmount
    }

    /// Check if this is a multi-path payment quote
    var isMPP: Bool {
        mppAmount != nil
    }
}

// MARK: - API Response Models

/// Response for POST /v1/melt/quote/bolt11 (NUT-05)
struct MeltQuoteResponse: Codable, Sendable {
    /// Quote identifier
    let quote: String
    
    /// Amount to be paid (from invoice)
    let amount: Int
    
    /// Fee reserve (maximum routing fee)
    let feeReserve: Int
    
    /// Unit of the tokens
    let unit: String
    
    /// Current state
    let state: MeltQuoteState
    
    /// Expiry timestamp (Unix seconds)
    let expiry: Int
    
    /// Payment preimage (if paid)
    let paymentPreimage: String?
    
    /// Change signatures (NUT-08) - returned overpaid fees
    let change: [BlindSignatureData]?
    
    enum CodingKeys: String, CodingKey {
        case quote, amount
        case feeReserve = "fee_reserve"
        case unit, state, expiry
        case paymentPreimage = "payment_preimage"
        case change
    }
    
    init(from quote: MeltQuote, change: [BlindSignatureData]? = nil) {
        self.quote = quote.quoteId
        self.amount = quote.amount
        self.feeReserve = quote.feeReserve
        self.unit = quote.unit
        self.state = quote.state
        self.expiry = Int(quote.expiry.timeIntervalSince1970)
        self.paymentPreimage = quote.paymentPreimage
        self.change = change
    }
}

/// Request for POST /v1/melt/quote/bolt11 (NUT-05, NUT-15)
struct MeltQuoteRequest: Codable, Sendable {
    /// Lightning invoice to pay
    let request: String

    /// Unit of the tokens to melt
    let unit: String

    /// Optional payment options (NUT-15 MPP)
    let options: MeltQuoteOptions?
}

/// Payment options for melt quotes (NUT-15)
struct MeltQuoteOptions: Codable, Sendable {
    /// Multi-path payment options
    let mpp: MPPOptions?
}

/// Multi-path payment options (NUT-15)
struct MPPOptions: Codable, Sendable {
    /// Partial amount to pay in millisats
    /// If specified, this mint will only pay this partial amount of the invoice
    let amount: Int
}

/// Request for POST /v1/melt/bolt11 (NUT-05)
struct MeltRequest: Codable, Sendable {
    /// Quote ID to melt tokens for
    let quote: String
    
    /// Proofs to spend
    let inputs: [ProofData]
    
    /// Optional blank outputs for fee return (NUT-08)
    let outputs: [BlindedMessageData]?
}

/// Response for POST /v1/melt/bolt11 (NUT-05)
struct MeltResponse: Codable, Sendable {
    /// Quote identifier
    let quote: String
    
    /// Amount paid
    let amount: Int
    
    /// Fee reserve
    let feeReserve: Int
    
    /// Current state (should be PAID on success)
    let state: MeltQuoteState
    
    /// Payment preimage (proof of payment)
    let paymentPreimage: String?
    
    /// Change signatures for overpaid fees (NUT-08)
    let change: [BlindSignatureData]?
    
    enum CodingKeys: String, CodingKey {
        case quote, amount
        case feeReserve = "fee_reserve"
        case state
        case paymentPreimage = "payment_preimage"
        case change
    }
}

// MARK: - Proof Data

/// Proof data from client (NUT-00)
struct ProofData: Codable, Sendable {
    /// Amount of this proof
    let amount: Int
    
    /// Keyset ID
    let id: String
    
    /// Secret (x) - the pre-image of Y
    let secret: String
    
    /// Unblinded signature (C) as hex
    let C: String
    
    /// Optional witness for spending conditions (NUT-10, NUT-11, NUT-14)
    let witness: String?
}
