import Foundation
import CryptoKit

/// Mock Lightning backend for testing
/// Simulates Lightning Network behavior without actual network calls
actor MockLightningBackend: LightningBackend {
    
    /// Stored invoices (payment hash -> invoice data)
    private var invoices: [String: MockInvoice] = [:]
    
    /// Stored payments (payment hash -> payment data)
    private var payments: [String: MockPayment] = [:]
    
    /// Simulated node balance in satoshis
    private var balance: Int
    
    /// Mock node public key
    private let nodePubkey: String
    
    /// Whether to auto-pay invoices (for testing mint flow)
    var autoPayInvoices: Bool = false
    
    /// Delay before auto-paying (simulates network delay)
    var autoPayDelay: TimeInterval = 0.1
    
    /// Whether payments should fail (for testing error handling)
    var simulatePaymentFailure: Bool = false
    
    /// Payment failure reason
    var paymentFailureReason: String = "Simulated failure"
    
    init(initialBalance: Int = 1_000_000) {
        self.balance = initialBalance
        // Generate a fake node pubkey
        self.nodePubkey = Self.generateRandomHex(length: 66)
    }
    
    // MARK: - Invoice Creation
    
    func createInvoice(amountSat: Int, memo: String?, expirySecs: Int) async throws -> CreateInvoiceResult {
        guard amountSat > 0 else {
            throw LightningError.invalidAmount("Amount must be positive")
        }
        
        // Generate random payment hash and preimage
        let preimage = Self.generateRandomBytes(count: 32)
        let paymentHash = SHA256.hash(data: preimage).hexString
        
        // Create mock bolt11 (not a real invoice, just for testing)
        let bolt11 = "lnbc\(amountSat)n1mock\(paymentHash.prefix(20))"
        
        let expiry = Date().addingTimeInterval(TimeInterval(expirySecs))
        
        let invoice = MockInvoice(
            paymentHash: paymentHash,
            preimage: preimage.hexString,
            amountSat: amountSat,
            memo: memo,
            bolt11: bolt11,
            expiry: expiry,
            status: .pending
        )
        
        invoices[paymentHash] = invoice
        
        // Auto-pay if enabled (for testing)
        if autoPayInvoices {
            Task {
                try? await Task.sleep(for: .seconds(autoPayDelay))
                await markInvoicePaid(paymentHash: paymentHash)
            }
        }
        
        return CreateInvoiceResult(
            bolt11: bolt11,
            paymentHash: paymentHash,
            expiry: expiry
        )
    }
    
    // MARK: - Invoice Status
    
    func getInvoiceStatus(paymentHash: String) async throws -> InvoiceStatus {
        guard let invoice = invoices[paymentHash] else {
            throw LightningError.invoiceNotFound(paymentHash)
        }
        
        // Check if expired
        if invoice.status == .pending && invoice.expiry < Date() {
            var updatedInvoice = invoice
            updatedInvoice.status = .expired
            invoices[paymentHash] = updatedInvoice
            return .expired
        }
        
        return invoice.status
    }
    
    func isInvoicePaid(paymentHash: String) async throws -> Bool {
        let status = try await getInvoiceStatus(paymentHash: paymentHash)
        return status == .paid
    }
    
    // MARK: - Invoice Decoding
    
    func decodeInvoice(bolt11: String) async throws -> DecodedInvoice {
        // For mock, we'll parse our mock format or generate fake data
        // In reality, this would decode a real BOLT11 invoice
        
        // Try to find if this is one of our created invoices
        for (_, invoice) in invoices {
            if invoice.bolt11 == bolt11 {
                return DecodedInvoice(
                    paymentHash: invoice.paymentHash,
                    amountMsat: Int64(invoice.amountSat) * 1000,
                    description: invoice.memo,
                    expiry: invoice.expiry,
                    destination: nodePubkey,
                    bolt11: bolt11
                )
            }
        }
        
        // Generate fake decoded invoice for external invoices
        let paymentHash = Self.generateRandomHex(length: 64)
        
        // Try to extract amount from mock format "lnbc{amount}n1mock..."
        var amountSat: Int? = nil
        if bolt11.hasPrefix("lnbc") {
            let afterPrefix = bolt11.dropFirst(4)
            if let nIndex = afterPrefix.firstIndex(of: "n") {
                let amountStr = String(afterPrefix.prefix(upTo: nIndex))
                amountSat = Int(amountStr)
            }
        }
        
        return DecodedInvoice(
            paymentHash: paymentHash,
            amountMsat: amountSat.map { Int64($0) * 1000 },
            description: "External invoice",
            expiry: Date().addingTimeInterval(3600),
            destination: Self.generateRandomHex(length: 66),
            bolt11: bolt11
        )
    }
    
    // MARK: - Payment
    
    func payInvoice(bolt11: String, maxFeeSat: Int, timeoutSecs: Int) async throws -> PaymentResult {
        // Decode the invoice first
        let decoded = try await decodeInvoice(bolt11: bolt11)
        
        guard let amountSat = decoded.amountSat else {
            throw LightningError.invalidAmount("Invoice has no amount")
        }
        
        // Check if we should simulate failure
        if simulatePaymentFailure {
            let payment = MockPayment(
                paymentHash: decoded.paymentHash,
                amountSat: amountSat,
                status: .failed,
                preimage: nil,
                feeSat: nil,
                error: paymentFailureReason
            )
            payments[decoded.paymentHash] = payment
            
            return PaymentResult(
                status: .failed,
                preimage: nil,
                feeSat: nil,
                feeMsat: nil,
                error: paymentFailureReason
            )
        }
        
        // Check balance
        let estimatedFee = min(maxFeeSat, max(1, amountSat / 100)) // 1% fee estimate
        let totalRequired = amountSat + estimatedFee
        
        guard balance >= totalRequired else {
            throw LightningError.insufficientBalance
        }
        
        // Simulate payment delay
        try? await Task.sleep(for: .milliseconds(100))
        
        // Deduct from balance
        balance -= (amountSat + estimatedFee)
        
        // Generate preimage (in reality, this comes from the recipient)
        let preimage = Self.generateRandomHex(length: 64)
        
        let payment = MockPayment(
            paymentHash: decoded.paymentHash,
            amountSat: amountSat,
            status: .succeeded,
            preimage: preimage,
            feeSat: estimatedFee,
            error: nil
        )
        payments[decoded.paymentHash] = payment
        
        return PaymentResult(
            status: .succeeded,
            preimage: preimage,
            feeSat: estimatedFee,
            feeMsat: Int64(estimatedFee) * 1000,
            error: nil
        )
    }
    
    func getPaymentStatus(paymentHash: String) async throws -> PaymentResult {
        guard let payment = payments[paymentHash] else {
            return PaymentResult(
                status: .pending,
                preimage: nil,
                feeSat: nil,
                feeMsat: nil,
                error: nil
            )
        }
        
        return PaymentResult(
            status: payment.status,
            preimage: payment.preimage,
            feeSat: payment.feeSat,
            feeMsat: payment.feeSat.map { Int64($0) * 1000 },
            error: payment.error
        )
    }
    
    // MARK: - Node Info
    
    func getNodePubkey() async throws -> String {
        return nodePubkey
    }
    
    func isReady() async throws -> Bool {
        return true
    }
    
    func getBalance() async throws -> Int {
        return balance
    }
    
    // MARK: - Test Helpers
    
    /// Manually mark an invoice as paid (for testing)
    func markInvoicePaid(paymentHash: String) async {
        guard var invoice = invoices[paymentHash] else { return }
        invoice.status = .paid
        invoices[paymentHash] = invoice
    }
    
    /// Add funds to the mock wallet
    func addFunds(amountSat: Int) async {
        balance += amountSat
    }
    
    /// Get the preimage for an invoice (for testing melt flow)
    func getPreimage(paymentHash: String) async -> String? {
        return invoices[paymentHash]?.preimage
    }
    
    /// Reset all state
    func reset() async {
        invoices.removeAll()
        payments.removeAll()
        balance = 1_000_000
    }
    
    // MARK: - Private Helpers
    
    private static func generateRandomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
    
    private static func generateRandomHex(length: Int) -> String {
        let bytes = generateRandomBytes(count: length / 2)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Mock Data Structures

private struct MockInvoice {
    let paymentHash: String
    let preimage: String
    let amountSat: Int
    let memo: String?
    let bolt11: String
    let expiry: Date
    var status: InvoiceStatus
}

private struct MockPayment {
    let paymentHash: String
    let amountSat: Int
    let status: PaymentStatus
    let preimage: String?
    let feeSat: Int?
    let error: String?
}

// MARK: - SHA256 Extension

private extension SHA256Digest {
    var hexString: String {
        self.map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    var hexString: String {
        self.map { String(format: "%02x", $0) }.joined()
    }
}
