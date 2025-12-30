import Foundation

/// Error types for Lightning operations
enum LightningError: Error, CustomStringConvertible {
    case invoiceCreationFailed(String)
    case invoiceDecodeFailed(String)
    case paymentFailed(String)
    case paymentPending
    case paymentTimeout
    case invoiceNotFound(String)
    case invoiceExpired
    case invoiceAlreadyPaid
    case connectionFailed(String)
    case insufficientBalance
    case routeNotFound
    case invalidAmount(String)
    
    var description: String {
        switch self {
        case .invoiceCreationFailed(let reason):
            return "Failed to create invoice: \(reason)"
        case .invoiceDecodeFailed(let reason):
            return "Failed to decode invoice: \(reason)"
        case .paymentFailed(let reason):
            return "Payment failed: \(reason)"
        case .paymentPending:
            return "Payment is pending"
        case .paymentTimeout:
            return "Payment timed out"
        case .invoiceNotFound(let hash):
            return "Invoice not found: \(hash)"
        case .invoiceExpired:
            return "Invoice has expired"
        case .invoiceAlreadyPaid:
            return "Invoice has already been paid"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .insufficientBalance:
            return "Insufficient balance"
        case .routeNotFound:
            return "No route found to destination"
        case .invalidAmount(let reason):
            return "Invalid amount: \(reason)"
        }
    }
}

/// Status of a Lightning invoice
enum InvoiceStatus: String, Sendable {
    case pending = "PENDING"
    case paid = "PAID"
    case expired = "EXPIRED"
    case cancelled = "CANCELLED"
}

/// Status of a Lightning payment
enum PaymentStatus: String, Sendable {
    case pending = "PENDING"
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
}

/// Decoded Lightning invoice information
struct DecodedInvoice: Sendable {
    /// Payment hash (hex)
    let paymentHash: String
    
    /// Amount in millisatoshis (nil for "any amount" invoices)
    let amountMsat: Int64?
    
    /// Amount in satoshis (nil for "any amount" invoices)
    var amountSat: Int? {
        guard let msat = amountMsat else { return nil }
        return Int(msat / 1000)
    }
    
    /// Invoice description
    let description: String?
    
    /// Expiry timestamp
    let expiry: Date
    
    /// Destination public key (hex)
    let destination: String
    
    /// The original bolt11 string
    let bolt11: String
}

/// Result of creating an invoice
struct CreateInvoiceResult: Sendable {
    /// The bolt11 invoice string
    let bolt11: String
    
    /// Payment hash (hex)
    let paymentHash: String
    
    /// When the invoice expires
    let expiry: Date
}

/// Result of paying an invoice
struct PaymentResult: Sendable {
    /// Payment status
    let status: PaymentStatus
    
    /// Payment preimage (hex) - only available if succeeded
    let preimage: String?
    
    /// Fee paid in satoshis - only available if succeeded
    let feeSat: Int?
    
    /// Fee paid in millisatoshis - only available if succeeded
    let feeMsat: Int64?
    
    /// Error message if failed
    let error: String?
}

/// Protocol defining the Lightning backend interface
/// All mint Lightning operations go through this protocol
protocol LightningBackend: Actor {
    
    // MARK: - Invoice Creation (for minting)
    
    /// Create a new Lightning invoice for receiving payment
    /// - Parameters:
    ///   - amountSat: Amount in satoshis
    ///   - memo: Optional description/memo for the invoice
    ///   - expirySecs: Seconds until invoice expires (default: 3600 = 1 hour)
    /// - Returns: Created invoice details
    func createInvoice(amountSat: Int, memo: String?, expirySecs: Int) async throws -> CreateInvoiceResult
    
    // MARK: - Invoice Status (for minting)
    
    /// Check the status of an invoice by payment hash
    /// - Parameter paymentHash: The payment hash (hex) to check
    /// - Returns: Current invoice status
    func getInvoiceStatus(paymentHash: String) async throws -> InvoiceStatus
    
    /// Check if an invoice has been paid
    /// - Parameter paymentHash: The payment hash (hex) to check
    /// - Returns: True if the invoice has been paid
    func isInvoicePaid(paymentHash: String) async throws -> Bool
    
    // MARK: - Invoice Decoding (for melting)
    
    /// Decode a bolt11 invoice string
    /// - Parameter bolt11: The bolt11 invoice string
    /// - Returns: Decoded invoice information
    func decodeInvoice(bolt11: String) async throws -> DecodedInvoice
    
    // MARK: - Payment (for melting)
    
    /// Pay a Lightning invoice
    /// - Parameters:
    ///   - bolt11: The bolt11 invoice to pay
    ///   - maxFeeSat: Maximum fee willing to pay in satoshis
    ///   - timeoutSecs: Payment timeout in seconds
    /// - Returns: Payment result
    func payInvoice(bolt11: String, maxFeeSat: Int, timeoutSecs: Int) async throws -> PaymentResult
    
    /// Get the status of an outgoing payment
    /// - Parameter paymentHash: The payment hash (hex)
    /// - Returns: Payment result with current status
    func getPaymentStatus(paymentHash: String) async throws -> PaymentResult
    
    // MARK: - Node Info
    
    /// Get the node's public key
    /// - Returns: Node public key as hex string
    func getNodePubkey() async throws -> String
    
    /// Check if the backend is connected and ready
    /// - Returns: True if ready to process payments
    func isReady() async throws -> Bool
    
    /// Get the node's current balance in satoshis
    /// - Returns: Spendable balance in satoshis
    func getBalance() async throws -> Int
}

// MARK: - Default Implementations

extension LightningBackend {
    /// Default expiry of 1 hour
    func createInvoice(amountSat: Int, memo: String?) async throws -> CreateInvoiceResult {
        try await createInvoice(amountSat: amountSat, memo: memo, expirySecs: 3600)
    }
    
    /// Convenience method using isInvoicePaid
    func isInvoicePaid(paymentHash: String) async throws -> Bool {
        let status = try await getInvoiceStatus(paymentHash: paymentHash)
        return status == .paid
    }
    
    /// Default payment with 60 second timeout
    func payInvoice(bolt11: String, maxFeeSat: Int) async throws -> PaymentResult {
        try await payInvoice(bolt11: bolt11, maxFeeSat: maxFeeSat, timeoutSecs: 60)
    }
}
