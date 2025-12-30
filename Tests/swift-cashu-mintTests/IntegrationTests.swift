import Testing
import Foundation
import Hummingbird
import HummingbirdTesting
@testable import swift_cashu_mint

/// Integration tests for API response models and structures
/// Full end-to-end tests require a database connection
@Suite("Integration Tests")
struct IntegrationTests {
    
    // MARK: - Response Model Tests
    
    @Test("HealthResponse encoding")
    func healthResponseEncoding() throws {
        let response = HealthResponse(
            status: "ok",
            timestamp: "2025-12-30T00:00:00Z"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json?["status"] as? String == "ok")
        #expect(json?["timestamp"] as? String == "2025-12-30T00:00:00Z")
    }
    
    // MARK: - GetInfoResponse Tests (NUT-06)
    
    @Test("GetInfoResponse encoding has correct keys")
    func getInfoResponseEncoding() throws {
        let response = GetInfoResponse(
            name: "Test Mint",
            pubkey: "02abc123",
            version: "SwiftMint/0.1.0",
            description: "A test mint",
            descriptionLong: "A longer description",
            contact: [["email": "test@example.com"]],
            motd: "Welcome!",
            iconUrl: "https://example.com/icon.png",
            tosUrl: "https://example.com/tos",
            nuts: NutsInfo(
                nut4: NUT4Info(
                    methods: [PaymentMethodInfo(method: "bolt11", unit: "sat", minAmount: 1, maxAmount: 1000000)],
                    disabled: false
                ),
                nut5: NUT5Info(
                    methods: [PaymentMethodInfo(method: "bolt11", unit: "sat", minAmount: 1, maxAmount: 1000000)],
                    disabled: false
                ),
                nut7: NUTSupportInfo(supported: true),
                nut8: NUTSupportInfo(supported: true),
                nut9: NUTSupportInfo(supported: true)
            )
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json?["name"] as? String == "Test Mint")
        #expect(json?["pubkey"] as? String == "02abc123")
        #expect(json?["version"] as? String == "SwiftMint/0.1.0")
        #expect(json?["description"] as? String == "A test mint")
        #expect(json?["description_long"] as? String == "A longer description")
        #expect(json?["motd"] as? String == "Welcome!")
        #expect(json?["icon_url"] as? String == "https://example.com/icon.png")
        #expect(json?["tos_url"] as? String == "https://example.com/tos")
        
        // Check nuts are nested with numeric keys
        let nuts = json?["nuts"] as? [String: Any]
        #expect(nuts?["4"] != nil)
        #expect(nuts?["5"] != nil)
        #expect(nuts?["7"] != nil)
        #expect(nuts?["8"] != nil)
        #expect(nuts?["9"] != nil)
    }
    
    @Test("GetInfoResponse with minimal fields")
    func getInfoResponseMinimal() throws {
        let response = GetInfoResponse(
            name: "Minimal Mint",
            pubkey: nil,
            version: "SwiftMint/0.1.0",
            description: nil,
            descriptionLong: nil,
            contact: nil,
            motd: nil,
            iconUrl: nil,
            tosUrl: nil,
            nuts: NutsInfo(
                nut4: NUT4Info(methods: [], disabled: true),
                nut5: NUT5Info(methods: [], disabled: true),
                nut7: NUTSupportInfo(supported: false),
                nut8: NUTSupportInfo(supported: false),
                nut9: NUTSupportInfo(supported: false)
            )
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json?["name"] as? String == "Minimal Mint")
        // Optional fields should be null or missing
    }
    
    // MARK: - PaymentMethodInfo Tests
    
    @Test("PaymentMethodInfo encoding uses snake_case")
    func paymentMethodInfoEncoding() throws {
        let info = PaymentMethodInfo(
            method: "bolt11",
            unit: "sat",
            minAmount: 1,
            maxAmount: 1000000
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(info)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json?["method"] as? String == "bolt11")
        #expect(json?["unit"] as? String == "sat")
        #expect(json?["min_amount"] as? Int == 1)
        #expect(json?["max_amount"] as? Int == 1000000)
    }
    
    // MARK: - GetKeysResponse Tests (NUT-01)
    
    @Test("GetKeysResponse encoding")
    func getKeysResponseEncoding() throws {
        let response = GetKeysResponse(
            keysets: [
                KeysetResponse(
                    id: "009a1f293253e41e",
                    unit: "sat",
                    keys: [
                        "1": "02abc...",
                        "2": "03def...",
                        "4": "02ghi..."
                    ]
                )
            ]
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        let keysets = json?["keysets"] as? [[String: Any]]
        #expect(keysets?.count == 1)
        
        let first = keysets?[0]
        #expect(first?["id"] as? String == "009a1f293253e41e")
        #expect(first?["unit"] as? String == "sat")
        
        let keys = first?["keys"] as? [String: String]
        #expect(keys?["1"] == "02abc...")
        #expect(keys?["2"] == "03def...")
        #expect(keys?["4"] == "02ghi...")
    }
    
    // MARK: - GetKeysetsResponse Tests (NUT-02)
    
    @Test("GetKeysetsResponse encoding uses snake_case")
    func getKeysetsResponseEncoding() throws {
        let response = GetKeysetsResponse(
            keysets: [
                KeysetInfo(
                    id: "009a1f293253e41e",
                    unit: "sat",
                    active: true,
                    inputFeePpk: 100
                ),
                KeysetInfo(
                    id: "0042ade98b2a370a",
                    unit: "sat",
                    active: false,
                    inputFeePpk: 100
                )
            ]
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        let keysets = json?["keysets"] as? [[String: Any]]
        #expect(keysets?.count == 2)
        
        let first = keysets?[0]
        #expect(first?["id"] as? String == "009a1f293253e41e")
        #expect(first?["active"] as? Bool == true)
        #expect(first?["input_fee_ppk"] as? Int == 100)
        
        let second = keysets?[1]
        #expect(second?["active"] as? Bool == false)
    }
    
    @Test("KeysetInfo with nil fee encodes properly")
    func keysetInfoNilFee() throws {
        let info = KeysetInfo(
            id: "testkeyset",
            unit: "sat",
            active: true,
            inputFeePpk: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(info)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // nil should encode as null or be omitted
        #expect(json?["id"] as? String == "testkeyset")
        #expect(json?["active"] as? Bool == true)
    }
    
    // MARK: - Error Response Tests
    
    @Test("CashuMintError has correct error codes")
    func cashuMintErrorCodes() {
        // From NUT error codes specification
        // For enum cases with associated values, we need to provide values
        #expect(CashuMintError.blindedMessageAlreadySigned.code == 10002)
        #expect(CashuMintError.tokenCouldNotBeVerified("test").code == 10003)
        #expect(CashuMintError.tokenAlreadySpent.code == 11001)
        #expect(CashuMintError.transactionNotBalanced(100, 90).code == 11002)
        #expect(CashuMintError.unitNotSupported("btc").code == 11005)
        #expect(CashuMintError.amountOutsideLimit(100, 1, 50).code == 11006)
        #expect(CashuMintError.keysetUnknown("unknown").code == 12001)
        #expect(CashuMintError.keysetInactive("inactive").code == 12002)
        #expect(CashuMintError.quoteNotPaid.code == 20001)
        #expect(CashuMintError.tokensAlreadyIssued.code == 20002)
        #expect(CashuMintError.mintingDisabled.code == 20003)
        #expect(CashuMintError.quoteExpired.code == 20007)
    }
    
    @Test("CashuMintError has descriptive messages")
    func cashuMintErrorMessages() {
        let errors: [CashuMintError] = [
            .blindedMessageAlreadySigned,
            .tokenCouldNotBeVerified("bad sig"),
            .tokenAlreadySpent,
            .transactionNotBalanced(100, 90),
            .unitNotSupported("btc"),
            .keysetUnknown("unknown"),
            .quoteNotPaid
        ]
        
        for error in errors {
            #expect(!error.detail.isEmpty)
        }
    }
    
    // MARK: - Quote Response Tests
    
    @Test("MintQuoteState raw values match NUT-04/NUT-23")
    func mintQuoteStateValues() {
        #expect(MintQuoteState.unpaid.rawValue == "UNPAID")
        #expect(MintQuoteState.paid.rawValue == "PAID")
        #expect(MintQuoteState.issued.rawValue == "ISSUED")
    }
    
    @Test("MeltQuoteState raw values match NUT-05/NUT-23")
    func meltQuoteStateValues() {
        #expect(MeltQuoteState.unpaid.rawValue == "UNPAID")
        #expect(MeltQuoteState.pending.rawValue == "PENDING")
        #expect(MeltQuoteState.paid.rawValue == "PAID")
    }
    
    // MARK: - Mock Lightning Backend Tests
    
    @Test("MockLightningBackend creates invoices")
    func mockLightningCreatesInvoices() async throws {
        let mock = MockLightningBackend()
        
        let invoice = try await mock.createInvoice(
            amountSat: 1000,
            memo: "Test invoice",
            expirySecs: 3600
        )
        
        #expect(invoice.bolt11.hasPrefix("lnbc"))
        #expect(!invoice.paymentHash.isEmpty)
        #expect(invoice.expiry > Date())
    }
    
    @Test("MockLightningBackend pays invoices")
    func mockLightningPaysInvoices() async throws {
        let mock = MockLightningBackend()
        
        // Create an invoice first
        let invoice = try await mock.createInvoice(amountSat: 100, memo: nil, expirySecs: 3600)
        
        // Pay it
        let result = try await mock.payInvoice(bolt11: invoice.bolt11, maxFeeSat: 10, timeoutSecs: 30)
        
        #expect(result.status == .succeeded)
        #expect(result.preimage != nil)
    }
    
    @Test("MockLightningBackend decodes invoices")
    func mockLightningDecodesInvoices() async throws {
        let mock = MockLightningBackend()
        
        // Create an invoice
        let invoice = try await mock.createInvoice(amountSat: 500, memo: "Decode test", expirySecs: 3600)
        
        // Decode it
        let decoded = try await mock.decodeInvoice(bolt11: invoice.bolt11)
        
        #expect(decoded.amountSat == 500)
        #expect(decoded.description == "Decode test")
    }
    
    @Test("MockLightningBackend tracks invoice status")
    func mockLightningTracksStatus() async throws {
        let mock = MockLightningBackend()
        
        // Create invoice
        let invoice = try await mock.createInvoice(amountSat: 100, memo: nil, expirySecs: 3600)
        
        // Initially should be pending
        let status = try await mock.getInvoiceStatus(paymentHash: invoice.paymentHash)
        
        #expect(status == .pending)
    }
    
    @Test("MockLightningBackend marks invoices as paid")
    func mockLightningMarksInvoicesPaid() async throws {
        let mock = MockLightningBackend()
        
        // Create invoice
        let invoice = try await mock.createInvoice(amountSat: 100, memo: nil, expirySecs: 3600)
        
        // Mark as paid
        await mock.markInvoicePaid(paymentHash: invoice.paymentHash)
        
        // Should now be paid
        let isPaid = try await mock.isInvoicePaid(paymentHash: invoice.paymentHash)
        #expect(isPaid)
    }
    
    @Test("MockLightningBackend deducts balance on payment")
    func mockLightningDeductsBalance() async throws {
        let initialBalance = 10000
        let mock = MockLightningBackend(initialBalance: initialBalance)
        
        // Create invoice (external)
        let invoice = try await mock.createInvoice(amountSat: 1000, memo: nil, expirySecs: 3600)
        
        // Pay it
        let result = try await mock.payInvoice(bolt11: invoice.bolt11, maxFeeSat: 100, timeoutSecs: 30)
        #expect(result.status == .succeeded)
        
        // Balance should be reduced
        let newBalance = try await mock.getBalance()
        #expect(newBalance < initialBalance)
    }
    
    @Test("MockLightningBackend balance tracking")
    func mockLightningBalanceTracking() async throws {
        let initialBalance = 10000
        let mock = MockLightningBackend(initialBalance: initialBalance)
        
        // Check initial balance
        let balance = try await mock.getBalance()
        #expect(balance == initialBalance)
        
        // Add funds
        await mock.addFunds(amountSat: 5000)
        let newBalance = try await mock.getBalance()
        #expect(newBalance == initialBalance + 5000)
    }
    
    @Test("MockLightningBackend is ready")
    func mockLightningIsReady() async throws {
        let mock = MockLightningBackend()
        let ready = try await mock.isReady()
        #expect(ready)
    }
    
    @Test("MockLightningBackend has node pubkey")
    func mockLightningHasNodePubkey() async throws {
        let mock = MockLightningBackend()
        let pubkey = try await mock.getNodePubkey()
        
        // Should be a hex string (66 chars for compressed pubkey)
        #expect(pubkey.count == 66)
    }
}
