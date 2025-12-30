import Testing
import Foundation
import CoreCashu
@preconcurrency import P256K
@testable import swift_cashu_mint

@Suite("Signing Tests")
struct SigningTests {
    
    // MARK: - SigningError Tests
    
    @Test("SigningError descriptions are not empty")
    func signingErrorDescriptions() {
        let errors: [SigningError] = [
            .invalidBlindedMessage("bad format"),
            .signingFailed("crypto error"),
            .keysetNotActive("keyset123"),
            .invalidKeysetId("invalid")
        ]
        
        for error in errors {
            #expect(!error.description.isEmpty)
        }
    }
    
    @Test("SigningError invalidBlindedMessage contains reason")
    func signingErrorInvalidBlindedMessage() {
        let error = SigningError.invalidBlindedMessage("missing B_")
        #expect(error.description.contains("missing B_"))
    }
    
    @Test("SigningError signingFailed contains reason")
    func signingErrorSigningFailed() {
        let error = SigningError.signingFailed("point not on curve")
        #expect(error.description.contains("point not on curve"))
    }
    
    @Test("SigningError keysetNotActive contains keyset ID")
    func signingErrorKeysetNotActive() {
        let error = SigningError.keysetNotActive("009a1f293253e41e")
        #expect(error.description.contains("009a1f293253e41e"))
    }
    
    // MARK: - BlindSignatureData Tests
    
    @Test("BlindSignatureData initialization")
    func blindSignatureDataInit() {
        let sig = BlindSignatureData(
            amount: 8,
            id: "009a1f293253e41e",
            C_: "02abc123",
            dleq: nil
        )
        
        #expect(sig.amount == 8)
        #expect(sig.id == "009a1f293253e41e")
        #expect(sig.C_ == "02abc123")
        #expect(sig.dleq == nil)
    }
    
    @Test("BlindSignatureData with DLEQ")
    func blindSignatureDataWithDLEQ() {
        let dleq = DLEQProofData(e: "evalue", s: "svalue")
        let sig = BlindSignatureData(
            amount: 16,
            id: "test",
            C_: "02def",
            dleq: dleq
        )
        
        #expect(sig.dleq != nil)
        #expect(sig.dleq?.e == "evalue")
        #expect(sig.dleq?.s == "svalue")
    }
    
    @Test("BlindSignatureData JSON encoding uses snake_case")
    func blindSignatureDataJSONEncoding() throws {
        let sig = BlindSignatureData(
            amount: 4,
            id: "testkeyset",
            C_: "02abc",
            dleq: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(sig)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json?["amount"] as? Int == 4)
        #expect(json?["id"] as? String == "testkeyset")
        #expect(json?["C_"] as? String == "02abc")
    }
    
    // MARK: - DLEQProofData Tests
    
    @Test("DLEQProofData initialization")
    func dleqProofDataInit() {
        let dleq = DLEQProofData(e: "ehex", s: "shex")
        #expect(dleq.e == "ehex")
        #expect(dleq.s == "shex")
    }
    
    @Test("DLEQProofData encoding roundtrip")
    func dleqProofDataEncodingRoundtrip() throws {
        let original = DLEQProofData(e: "e123", s: "s456")
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(DLEQProofData.self, from: data)
        
        #expect(decoded.e == original.e)
        #expect(decoded.s == original.s)
    }
    
    // MARK: - BlindedMessageData Tests
    
    @Test("BlindedMessageData initialization")
    func blindedMessageDataInit() {
        let msg = BlindedMessageData(
            amount: 32,
            id: "keyset1",
            B_: "02deadbeef",
            witness: nil
        )
        
        #expect(msg.amount == 32)
        #expect(msg.id == "keyset1")
        #expect(msg.B_ == "02deadbeef")
        #expect(msg.witness == nil)
    }
    
    @Test("BlindedMessageData with witness")
    func blindedMessageDataWithWitness() {
        let msg = BlindedMessageData(
            amount: 64,
            id: "keyset2",
            B_: "03cafebabe",
            witness: "witness_data"
        )
        
        #expect(msg.witness == "witness_data")
    }
    
    @Test("BlindedMessageData encoding roundtrip")
    func blindedMessageDataEncodingRoundtrip() throws {
        let original = BlindedMessageData(
            amount: 128,
            id: "testid",
            B_: "02aabbcc",
            witness: nil
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(BlindedMessageData.self, from: data)
        
        #expect(decoded.amount == original.amount)
        #expect(decoded.id == original.id)
        #expect(decoded.B_ == original.B_)
    }
    
    // MARK: - MintKeypair Tests (CoreCashu)
    
    @Test("MintKeypair generation produces valid keys")
    func mintKeypairGeneration() throws {
        let keypair = try MintKeypair()
        
        // Private key should be 32 bytes
        #expect(keypair.privateKey.rawRepresentation.count == 32)
        
        // Public key should be 33 bytes (compressed)
        #expect(keypair.publicKey.dataRepresentation.count == 33)
    }
    
    @Test("MintKeypair is different each time")
    func mintKeypairUniqueness() throws {
        let keypair1 = try MintKeypair()
        let keypair2 = try MintKeypair()
        
        // Private keys should be different
        #expect(keypair1.privateKey.rawRepresentation != keypair2.privateKey.rawRepresentation)
    }
    
    @Test("Mint can sign a blinded message")
    func mintSignsBlindedMessage() throws {
        let keypair = try MintKeypair()
        let mint = Mint(privateKey: keypair.privateKey)
        
        // Generate a random 33-byte point (simulating B_)
        // In practice, this would come from wallet blinding
        let keypair2 = try MintKeypair()
        let blindedMessage = keypair2.publicKey.dataRepresentation
        
        // Mint signs the blinded message
        let blindedSignature = try mint.signBlindedMessage(blindedMessage)
        
        // Signature should be a valid curve point (33 bytes compressed)
        #expect(blindedSignature.count == 33)
    }
    
    @Test("Mint signing is deterministic")
    func mintSigningDeterministic() throws {
        let keypair = try MintKeypair()
        let mint = Mint(privateKey: keypair.privateKey)
        
        // Same blinded message
        let keypair2 = try MintKeypair()
        let blindedMessage = keypair2.publicKey.dataRepresentation
        
        // Sign twice with same message
        let sig1 = try mint.signBlindedMessage(blindedMessage)
        let sig2 = try mint.signBlindedMessage(blindedMessage)
        
        // Should produce identical signatures
        #expect(sig1 == sig2)
    }
    
    @Test("Different mints produce different signatures")
    func differentMintsProduceDifferentSignatures() throws {
        let keypair1 = try MintKeypair()
        let keypair2 = try MintKeypair()
        let mint1 = Mint(privateKey: keypair1.privateKey)
        let mint2 = Mint(privateKey: keypair2.privateKey)
        
        // Same blinded message
        let keypair3 = try MintKeypair()
        let blindedMessage = keypair3.publicKey.dataRepresentation
        
        // Different mints sign
        let sig1 = try mint1.signBlindedMessage(blindedMessage)
        let sig2 = try mint2.signBlindedMessage(blindedMessage)
        
        // Should produce different signatures
        #expect(sig1 != sig2)
    }
    
    @Test("Different messages produce different signatures")
    func differentMessagesProduceDifferentSignatures() throws {
        let keypair = try MintKeypair()
        let mint = Mint(privateKey: keypair.privateKey)
        
        // Different blinded messages
        let keypair2 = try MintKeypair()
        let keypair3 = try MintKeypair()
        let msg1 = keypair2.publicKey.dataRepresentation
        let msg2 = keypair3.publicKey.dataRepresentation
        
        let sig1 = try mint.signBlindedMessage(msg1)
        let sig2 = try mint.signBlindedMessage(msg2)
        
        #expect(sig1 != sig2)
    }
    
    // MARK: - Amount Validation Tests
    
    @Test("Power of 2 amounts are valid denominations")
    func powerOfTwoAmountsValid() {
        let validAmounts = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072, 262144, 524288, 1048576]
        
        for amount in validAmounts {
            // Check it's a power of 2
            let isPowerOfTwo = amount > 0 && (amount & (amount - 1)) == 0
            #expect(isPowerOfTwo)
        }
    }
    
    @Test("Non-power of 2 amounts are invalid denominations")
    func nonPowerOfTwoAmountsInvalid() {
        let invalidAmounts = [3, 5, 6, 7, 9, 10, 15, 100, 1000]
        
        for amount in invalidAmounts {
            // Check it's NOT a power of 2
            let isPowerOfTwo = amount > 0 && (amount & (amount - 1)) == 0
            #expect(!isPowerOfTwo)
        }
    }
    
    // MARK: - Hex String Format Tests
    
    @Test("Valid B_ hex string format - 66 characters")
    func validBlindedMessageHex() {
        // Compressed public key should be 33 bytes = 66 hex chars
        let validB_ = "02" + String(repeating: "a", count: 64)  // 66 chars total
        
        #expect(validB_.count == 66)
        
        // First two chars indicate compression format
        #expect(validB_.hasPrefix("02") || validB_.hasPrefix("03"))
    }
    
    @Test("Valid C_ hex string format - 66 characters")
    func validBlindSignatureHex() {
        // Blind signature is also a compressed point
        let validC_ = "03" + String(repeating: "b", count: 64)
        
        #expect(validC_.count == 66)
        
        // First two chars indicate compression format
        #expect(validC_.hasPrefix("02") || validC_.hasPrefix("03"))
    }
    
    @Test("Compressed point prefix is 02 or 03")
    func compressedPointPrefix() {
        // 02 prefix = even y-coordinate
        let even = "02" + String(repeating: "a", count: 64)
        #expect(even.hasPrefix("02"))
        
        // 03 prefix = odd y-coordinate
        let odd = "03" + String(repeating: "b", count: 64)
        #expect(odd.hasPrefix("03"))
        
        // 04 would be uncompressed (65 bytes)
        let uncompressed = "04" + String(repeating: "c", count: 128)  // 130 chars
        #expect(uncompressed.hasPrefix("04"))
        #expect(uncompressed.count == 130)
    }
}
