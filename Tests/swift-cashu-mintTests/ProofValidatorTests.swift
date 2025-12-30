import Testing
import Foundation
@testable import swift_cashu_mint

@Suite("ProofValidator Tests")
struct ProofValidatorTests {
    
    // MARK: - ProofValidationError Tests
    
    @Test("ProofValidationError descriptions are not empty")
    func proofValidationErrorDescriptions() {
        let errors: [ProofValidationError] = [
            .invalidSignature,
            .proofAlreadySpent("y123"),
            .proofIsPending("y456"),
            .unknownKeyset("keyset789"),
            .invalidSecret("bad format"),
            .invalidC("not hex"),
            .amountMismatch(expected: 8, got: 4),
            .duplicateProof("y_duplicate")
        ]
        
        for error in errors {
            #expect(!error.description.isEmpty)
        }
    }
    
    @Test("ProofValidationError proofAlreadySpent contains Y value")
    func proofValidationErrorSpentContainsY() {
        let error = ProofValidationError.proofAlreadySpent("abc123def456")
        #expect(error.description.contains("abc123def456"))
    }
    
    @Test("ProofValidationError proofIsPending contains Y value")
    func proofValidationErrorPendingContainsY() {
        let error = ProofValidationError.proofIsPending("pending123")
        #expect(error.description.contains("pending123"))
    }
    
    @Test("ProofValidationError unknownKeyset contains keyset ID")
    func proofValidationErrorUnknownKeysetContainsId() {
        let error = ProofValidationError.unknownKeyset("009a1f293253e41e")
        #expect(error.description.contains("009a1f293253e41e"))
    }
    
    @Test("ProofValidationError amountMismatch contains both amounts")
    func proofValidationErrorAmountMismatch() {
        let error = ProofValidationError.amountMismatch(expected: 16, got: 8)
        #expect(error.description.contains("16"))
        #expect(error.description.contains("8"))
    }
    
    @Test("ProofValidationError duplicateProof contains Y value")
    func proofValidationErrorDuplicateContainsY() {
        let error = ProofValidationError.duplicateProof("duplicate_y")
        #expect(error.description.contains("duplicate_y"))
    }
    
    // MARK: - ValidationResult Tests
    
    @Test("ValidationResult isAllValid returns true when no invalid")
    func validationResultAllValid() {
        let valid: [ProofData] = [
            ProofData(amount: 8, id: "test", secret: "s1", C: "c1", witness: nil),
            ProofData(amount: 4, id: "test", secret: "s2", C: "c2", witness: nil)
        ]
        let result = ValidationResult(valid: valid, invalid: [])
        
        #expect(result.isAllValid)
        #expect(result.valid.count == 2)
        #expect(result.invalid.isEmpty)
    }
    
    @Test("ValidationResult isAllValid returns false when has invalid")
    func validationResultHasInvalid() {
        let valid: [ProofData] = [
            ProofData(amount: 8, id: "test", secret: "s1", C: "c1", witness: nil)
        ]
        let invalid: [(ProofData, ProofValidationError)] = [
            (ProofData(amount: 4, id: "test", secret: "s2", C: "c2", witness: nil), .invalidSignature)
        ]
        let result = ValidationResult(valid: valid, invalid: invalid)
        
        #expect(!result.isAllValid)
        #expect(result.valid.count == 1)
        #expect(result.invalid.count == 1)
    }
    
    @Test("ValidationResult totalAmount sums valid proofs")
    func validationResultTotalAmount() {
        let valid: [ProofData] = [
            ProofData(amount: 8, id: "test", secret: "s1", C: "c1", witness: nil),
            ProofData(amount: 4, id: "test", secret: "s2", C: "c2", witness: nil),
            ProofData(amount: 16, id: "test", secret: "s3", C: "c3", witness: nil)
        ]
        let result = ValidationResult(valid: valid, invalid: [])
        
        #expect(result.totalAmount == 28)
    }
    
    @Test("ValidationResult totalAmount is zero when no valid")
    func validationResultTotalAmountEmpty() {
        let result = ValidationResult(valid: [], invalid: [])
        #expect(result.totalAmount == 0)
    }
    
    @Test("ValidationResult totalAmount ignores invalid proofs")
    func validationResultTotalAmountIgnoresInvalid() {
        let valid: [ProofData] = [
            ProofData(amount: 10, id: "test", secret: "s1", C: "c1", witness: nil)
        ]
        let invalid: [(ProofData, ProofValidationError)] = [
            (ProofData(amount: 100, id: "test", secret: "s2", C: "c2", witness: nil), .invalidSignature)
        ]
        let result = ValidationResult(valid: valid, invalid: invalid)
        
        // Should only sum valid proofs
        #expect(result.totalAmount == 10)
    }
    
    // MARK: - ProofState Tests
    
    @Test("ProofState raw values match NUT-07 spec")
    func proofStateRawValues() {
        #expect(ProofState.unspent.rawValue == "UNSPENT")
        #expect(ProofState.pending.rawValue == "PENDING")
        #expect(ProofState.spent.rawValue == "SPENT")
    }
    
    @Test("ProofState can be decoded from string")
    func proofStateDecoding() throws {
        let json = """
        {"state": "SPENT"}
        """
        
        struct Wrapper: Codable {
            let state: ProofState
        }
        
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Wrapper.self, from: data)
        
        #expect(decoded.state == .spent)
    }
    
    @Test("ProofState encodes to correct string")
    func proofStateEncoding() throws {
        struct Wrapper: Codable {
            let state: ProofState
        }
        
        let wrapper = Wrapper(state: .pending)
        let data = try JSONEncoder().encode(wrapper)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json?["state"] as? String == "PENDING")
    }
    
    // MARK: - ProofStateResponse Tests
    
    @Test("ProofStateResponse initialization")
    func proofStateResponseInit() {
        let response = ProofStateResponse(y: "02abc", state: .spent, witness: nil)
        
        #expect(response.y == "02abc")
        #expect(response.state == .spent)
        #expect(response.witness == nil)
    }
    
    @Test("ProofStateResponse with witness")
    func proofStateResponseWithWitness() {
        let response = ProofStateResponse(y: "03def", state: .spent, witness: "sig123")
        
        #expect(response.witness == "sig123")
    }
    
    @Test("ProofStateResponse encoding uses snake_case")
    func proofStateResponseEncoding() throws {
        let response = ProofStateResponse(y: "02xyz", state: .unspent, witness: nil)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json?["Y"] as? String == "02xyz")  // Note: Y is uppercase in NUT-07
        #expect(json?["state"] as? String == "UNSPENT")
    }
    
    // MARK: - ProofData Tests
    
    @Test("ProofData initialization")
    func proofDataInit() {
        let proof = ProofData(
            amount: 64,
            id: "009a1f293253e41e",
            secret: "secret_value",
            C: "02abcdef",
            witness: nil
        )
        
        #expect(proof.amount == 64)
        #expect(proof.id == "009a1f293253e41e")
        #expect(proof.secret == "secret_value")
        #expect(proof.C == "02abcdef")
        #expect(proof.witness == nil)
    }
    
    @Test("ProofData encoding roundtrip")
    func proofDataEncodingRoundtrip() throws {
        let original = ProofData(
            amount: 32,
            id: "testkeyset",
            secret: "my_secret",
            C: "03cafebabe",
            witness: nil
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ProofData.self, from: data)
        
        #expect(decoded.amount == original.amount)
        #expect(decoded.id == original.id)
        #expect(decoded.secret == original.secret)
        #expect(decoded.C == original.C)
    }
    
    @Test("ProofData with witness")
    func proofDataWithWitness() {
        let proof = ProofData(
            amount: 16,
            id: "keyset1",
            secret: "secret",
            C: "02abc",
            witness: "witness_data_here"
        )
        
        #expect(proof.witness == "witness_data_here")
    }
    
    // MARK: - Duplicate Detection Logic Tests
    
    @Test("Set can detect duplicate Y values")
    func setDetectsDuplicateYValues() {
        var seenYs: Set<String> = []
        
        let y1 = "02abc123"
        let y2 = "03def456"
        let y3 = "02abc123"  // Duplicate of y1
        
        #expect(!seenYs.contains(y1))
        seenYs.insert(y1)
        
        #expect(!seenYs.contains(y2))
        seenYs.insert(y2)
        
        #expect(seenYs.contains(y3))  // Should detect duplicate
    }
    
    // MARK: - Amount Power of 2 Validation
    
    @Test("Valid proof amounts are powers of 2")
    func validProofAmountsPowerOfTwo() {
        let validAmounts = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024]
        
        for amount in validAmounts {
            let isPowerOfTwo = amount > 0 && (amount & (amount - 1)) == 0
            #expect(isPowerOfTwo, "Amount \(amount) should be a power of 2")
        }
    }
    
    @Test("Invalid proof amounts are not powers of 2")
    func invalidProofAmountsNotPowerOfTwo() {
        let invalidAmounts = [0, 3, 5, 6, 7, 9, 10, 12, 15, 17, 100]
        
        for amount in invalidAmounts {
            let isPowerOfTwo = amount > 0 && (amount & (amount - 1)) == 0
            #expect(!isPowerOfTwo, "Amount \(amount) should not be a power of 2")
        }
    }
    
    // MARK: - Secret Format Tests
    
    @Test("Secret can be any string")
    func secretCanBeAnyString() {
        // Secrets can be any format - typically random hex or structured JSON
        let secrets = [
            "simple_secret",
            "429700b812a58436be2629af8731a31a37fce54dbf8cbbe90b3f8553179d23f5",
            "[\"P2PK\",{\"data\":\"02...\"}]",  // NUT-11 P2PK format
            "[\"HTLC\",{\"hash\":\"...\"}]"      // NUT-14 HTLC format
        ]
        
        for secret in secrets {
            let proof = ProofData(amount: 8, id: "test", secret: secret, C: "02abc", witness: nil)
            #expect(proof.secret == secret)
        }
    }
    
    // MARK: - C (Signature) Format Tests
    
    @Test("C should be valid hex compressed point")
    func cShouldBeHexCompressedPoint() {
        // C is the unblinded signature, a compressed curve point
        let validC = "02" + String(repeating: "a", count: 64)  // 66 hex chars
        
        #expect(validC.count == 66)
        #expect(validC.hasPrefix("02") || validC.hasPrefix("03"))
    }
}
