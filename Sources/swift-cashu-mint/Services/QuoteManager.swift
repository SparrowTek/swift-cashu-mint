import Foundation
import Fluent

/// Error types for quote management
enum QuoteError: Error, CustomStringConvertible {
    case quoteNotFound(String)
    case quoteExpired(String)
    case quoteNotPaid(String)
    case quoteAlreadyPaid(String)
    case quoteAlreadyIssued(String)
    case quotePending(String)
    case invalidAmount(String)
    case invalidState(expected: String, got: String)
    
    var description: String {
        switch self {
        case .quoteNotFound(let id):
            return "Quote not found: \(id)"
        case .quoteExpired(let id):
            return "Quote expired: \(id)"
        case .quoteNotPaid(let id):
            return "Quote not paid: \(id)"
        case .quoteAlreadyPaid(let id):
            return "Quote already paid: \(id)"
        case .quoteAlreadyIssued(let id):
            return "Tokens already issued for quote: \(id)"
        case .quotePending(let id):
            return "Quote payment is pending: \(id)"
        case .invalidAmount(let reason):
            return "Invalid amount: \(reason)"
        case .invalidState(let expected, let got):
            return "Invalid quote state: expected \(expected), got \(got)"
        }
    }
}

/// Service for managing mint and melt quotes
actor QuoteManager {
    private let database: Database
    private let config: MintConfiguration
    
    /// Default quote expiry time (1 hour)
    private let defaultExpirySeconds: TimeInterval = 3600
    
    init(database: Database, config: MintConfiguration) {
        self.database = database
        self.config = config
    }
    
    // MARK: - Mint Quotes (NUT-04)
    
    /// Create a new mint quote
    /// Lightning invoice creation is done externally by the Lightning backend
    func createMintQuote(
        amount: Int,
        unit: String,
        request: String,
        paymentHash: String,
        expiry: Date,
        description: String? = nil
    ) async throws -> MintQuote {
        // Validate amount within limits
        guard amount >= config.mintMinAmount else {
            throw QuoteError.invalidAmount("Amount \(amount) is below minimum \(config.mintMinAmount)")
        }
        guard amount <= config.mintMaxAmount else {
            throw QuoteError.invalidAmount("Amount \(amount) is above maximum \(config.mintMaxAmount)")
        }
        
        // Generate unique quote ID
        let quoteId = generateQuoteId()
        
        let quote = MintQuote(
            quoteId: quoteId,
            method: "bolt11",
            unit: unit,
            amount: amount,
            request: request,
            paymentHash: paymentHash,
            state: .unpaid,
            expiry: expiry,
            invoiceDescription: description
        )
        
        try await quote.save(on: database)
        
        return quote
    }
    
    /// Get a mint quote by ID
    func getMintQuote(id: String) async throws -> MintQuote {
        guard let quote = try await MintQuote.query(on: database)
            .filter(\.$quoteId == id)
            .first() else {
            throw QuoteError.quoteNotFound(id)
        }
        return quote
    }
    
    /// Get a mint quote by payment hash (for invoice payment callbacks)
    func getMintQuoteByPaymentHash(_ paymentHash: String) async throws -> MintQuote? {
        return try await MintQuote.query(on: database)
            .filter(\.$paymentHash == paymentHash)
            .first()
    }
    
    /// Mark a mint quote as paid (invoice was paid)
    func markMintQuoteAsPaid(id: String) async throws {
        guard let quote = try await MintQuote.query(on: database)
            .filter(\.$quoteId == id)
            .first() else {
            throw QuoteError.quoteNotFound(id)
        }
        
        guard quote.state == .unpaid else {
            if quote.state == .paid {
                return // Already paid, idempotent
            }
            throw QuoteError.quoteAlreadyIssued(id)
        }
        
        quote.state = .paid
        try await quote.save(on: database)
    }
    
    /// Mark a mint quote as paid by payment hash
    func markMintQuoteAsPaid(paymentHash: String) async throws {
        guard let quote = try await MintQuote.query(on: database)
            .filter(\.$paymentHash == paymentHash)
            .first() else {
            return // Quote not found, might be a different payment
        }
        
        if quote.state == .unpaid {
            quote.state = .paid
            try await quote.save(on: database)
        }
    }
    
    /// Mark a mint quote as issued (tokens were minted)
    func markMintQuoteAsIssued(id: String) async throws {
        guard let quote = try await MintQuote.query(on: database)
            .filter(\.$quoteId == id)
            .first() else {
            throw QuoteError.quoteNotFound(id)
        }
        
        guard quote.state == .paid else {
            if quote.state == .unpaid {
                throw QuoteError.quoteNotPaid(id)
            }
            if quote.state == .issued {
                throw QuoteError.quoteAlreadyIssued(id)
            }
            throw QuoteError.invalidState(expected: "PAID", got: quote.state.rawValue)
        }
        
        quote.state = .issued
        quote.issuedAt = Date()
        try await quote.save(on: database)
    }
    
    /// Check if a mint quote is ready for minting
    func validateMintQuoteForMinting(id: String) async throws -> MintQuote {
        let quote = try await getMintQuote(id: id)
        
        // Check expiry
        if quote.expiry < Date() {
            throw QuoteError.quoteExpired(id)
        }
        
        // Check state
        guard quote.state == .paid else {
            if quote.state == .unpaid {
                throw QuoteError.quoteNotPaid(id)
            }
            if quote.state == .issued {
                throw QuoteError.quoteAlreadyIssued(id)
            }
            throw QuoteError.invalidState(expected: "PAID", got: quote.state.rawValue)
        }
        
        return quote
    }
    
    // MARK: - Melt Quotes (NUT-05)
    
    /// Create a new melt quote
    func createMeltQuote(
        request: String,
        unit: String,
        amount: Int,
        feeReserve: Int,
        expiry: Date
    ) async throws -> MeltQuote {
        // Validate amount within limits
        guard amount >= config.meltMinAmount else {
            throw QuoteError.invalidAmount("Amount \(amount) is below minimum \(config.meltMinAmount)")
        }
        guard amount <= config.meltMaxAmount else {
            throw QuoteError.invalidAmount("Amount \(amount) is above maximum \(config.meltMaxAmount)")
        }
        
        // Generate unique quote ID
        let quoteId = generateQuoteId()
        
        let quote = MeltQuote(
            quoteId: quoteId,
            method: "bolt11",
            unit: unit,
            request: request,
            amount: amount,
            feeReserve: feeReserve,
            state: .unpaid,
            expiry: expiry
        )
        
        try await quote.save(on: database)
        
        return quote
    }
    
    /// Get a melt quote by ID
    func getMeltQuote(id: String) async throws -> MeltQuote {
        guard let quote = try await MeltQuote.query(on: database)
            .filter(\.$quoteId == id)
            .first() else {
            throw QuoteError.quoteNotFound(id)
        }
        return quote
    }
    
    /// Mark a melt quote as pending (payment in progress)
    func markMeltQuoteAsPending(id: String) async throws {
        guard let quote = try await MeltQuote.query(on: database)
            .filter(\.$quoteId == id)
            .first() else {
            throw QuoteError.quoteNotFound(id)
        }
        
        guard quote.state == .unpaid else {
            if quote.state == .pending {
                throw QuoteError.quotePending(id)
            }
            if quote.state == .paid {
                throw QuoteError.quoteAlreadyPaid(id)
            }
            throw QuoteError.invalidState(expected: "UNPAID", got: quote.state.rawValue)
        }
        
        quote.state = .pending
        try await quote.save(on: database)
    }
    
    /// Mark a melt quote as paid (Lightning payment succeeded)
    func markMeltQuoteAsPaid(id: String, preimage: String, feePaid: Int) async throws {
        guard let quote = try await MeltQuote.query(on: database)
            .filter(\.$quoteId == id)
            .first() else {
            throw QuoteError.quoteNotFound(id)
        }
        
        guard quote.state == .pending else {
            if quote.state == .paid {
                return // Idempotent
            }
            throw QuoteError.invalidState(expected: "PENDING", got: quote.state.rawValue)
        }
        
        quote.state = .paid
        quote.paymentPreimage = preimage
        quote.feePaid = feePaid
        quote.paidAt = Date()
        try await quote.save(on: database)
    }
    
    /// Mark a melt quote as failed (return to unpaid for retry)
    func markMeltQuoteAsFailed(id: String) async throws {
        guard let quote = try await MeltQuote.query(on: database)
            .filter(\.$quoteId == id)
            .first() else {
            throw QuoteError.quoteNotFound(id)
        }
        
        // Only pending quotes can fail
        guard quote.state == .pending else {
            return // Already in another state
        }
        
        quote.state = .unpaid
        try await quote.save(on: database)
    }
    
    /// Validate a melt quote for melting
    func validateMeltQuoteForMelting(id: String) async throws -> MeltQuote {
        let quote = try await getMeltQuote(id: id)
        
        // Check expiry
        if quote.expiry < Date() {
            throw QuoteError.quoteExpired(id)
        }
        
        // Check state
        guard quote.state == .unpaid else {
            if quote.state == .pending {
                throw QuoteError.quotePending(id)
            }
            if quote.state == .paid {
                throw QuoteError.quoteAlreadyPaid(id)
            }
            throw QuoteError.invalidState(expected: "UNPAID", got: quote.state.rawValue)
        }
        
        return quote
    }
    
    // MARK: - Cleanup
    
    /// Clean up expired quotes
    func cleanupExpiredQuotes() async throws -> (mintQuotes: Int, meltQuotes: Int) {
        let now = Date()
        
        // Delete expired unpaid mint quotes
        let expiredMintQuotes = try await MintQuote.query(on: database)
            .filter(\.$expiry < now)
            .filter(\.$state == .unpaid)
            .all()
        
        for quote in expiredMintQuotes {
            try await quote.delete(on: database)
        }
        
        // Delete expired unpaid melt quotes
        let expiredMeltQuotes = try await MeltQuote.query(on: database)
            .filter(\.$expiry < now)
            .filter(\.$state == .unpaid)
            .all()
        
        for quote in expiredMeltQuotes {
            try await quote.delete(on: database)
        }
        
        return (expiredMintQuotes.count, expiredMeltQuotes.count)
    }
    
    // MARK: - Helpers
    
    /// Generate a unique quote ID
    private func generateQuoteId() -> String {
        // Generate 16 random bytes and encode as hex
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
