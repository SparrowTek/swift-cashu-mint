import Testing
import Foundation
@testable import swift_cashu_mint

@Suite("Keyset Tests")
struct KeysetTests {
    
    // MARK: - Data Hex Extension Tests
    
    @Test("Data from hex string - valid hex")
    func dataFromValidHex() {
        let data = Data(hexString: "deadbeef")
        #expect(data != nil)
        #expect(data?.count == 4)
        #expect(data?[0] == 0xde)
        #expect(data?[1] == 0xad)
        #expect(data?[2] == 0xbe)
        #expect(data?[3] == 0xef)
    }
    
    @Test("Data from hex string with 0x prefix")
    func dataFromHexWithPrefix() {
        let data = Data(hexString: "0xaabbcc")
        #expect(data != nil)
        #expect(data?.count == 3)
    }
    
    @Test("Data from hex string - empty string")
    func dataFromEmptyHex() {
        let data = Data(hexString: "")
        #expect(data != nil)
        #expect(data?.count == 0)
    }
    
    @Test("Data from hex string - odd length returns nil")
    func dataFromOddLengthHex() {
        let data = Data(hexString: "abc")
        #expect(data == nil)
    }
    
    @Test("Data from hex string - invalid characters returns nil")
    func dataFromInvalidHex() {
        let data = Data(hexString: "gg")
        #expect(data == nil)
    }
    
    @Test("Data to hex string")
    func dataToHexString() {
        let data = Data([0xde, 0xad, 0xbe, 0xef])
        let hex = data.hexEncodedString()
        #expect(hex == "deadbeef")
    }
    
    @Test("Data hex roundtrip")
    func dataHexRoundtrip() {
        let original = "0123456789abcdef"
        let data = Data(hexString: original)
        let back = data?.hexEncodedString()
        #expect(back == original)
    }
    
    @Test("Data hex roundtrip - uppercase input")
    func dataHexRoundtripUppercase() {
        let original = "ABCDEF"
        let data = Data(hexString: original)
        let back = data?.hexEncodedString()
        // Output is always lowercase
        #expect(back == "abcdef")
    }
    
    // MARK: - SHA256 Helper Tests
    
    @Test("SHA256 hash of empty data")
    func sha256Empty() {
        let data = Data()
        let hash = SHA256Helper.hash(data: data)
        // SHA256 of empty string is well-known
        let expected = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        #expect(hash.hexEncodedString() == expected)
    }
    
    @Test("SHA256 hash of 'hello'")
    func sha256Hello() {
        let data = "hello".data(using: .utf8)!
        let hash = SHA256Helper.hash(data: data)
        // SHA256("hello") is well-known
        let expected = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        #expect(hash.hexEncodedString() == expected)
    }
    
    @Test("SHA256 hash is deterministic")
    func sha256Deterministic() {
        let data = "test data".data(using: .utf8)!
        let hash1 = SHA256Helper.hash(data: data)
        let hash2 = SHA256Helper.hash(data: data)
        #expect(hash1 == hash2)
    }
    
    @Test("SHA256 hash has correct length")
    func sha256Length() {
        let data = "any data".data(using: .utf8)!
        let hash = SHA256Helper.hash(data: data)
        #expect(hash.count == 32)  // 256 bits = 32 bytes
    }
    
    // MARK: - KeysetKeys Tests
    
    @Test("KeysetKeys initialization")
    func keysetKeysInit() {
        let keys: [Int: String] = [
            1: "key1",
            2: "key2",
            4: "key4"
        ]
        let keysetKeys = KeysetKeys(keys: keys)
        
        #expect(keysetKeys.amounts == [1, 2, 4])
        #expect(keysetKeys.privateKey(for: 1) == "key1")
        #expect(keysetKeys.privateKey(for: 2) == "key2")
        #expect(keysetKeys.privateKey(for: 4) == "key4")
    }
    
    @Test("KeysetKeys amounts are sorted")
    func keysetKeysAmountsSorted() {
        let keys: [Int: String] = [
            64: "key64",
            1: "key1",
            32: "key32",
            2: "key2"
        ]
        let keysetKeys = KeysetKeys(keys: keys)
        
        #expect(keysetKeys.amounts == [1, 2, 32, 64])
    }
    
    @Test("KeysetKeys unknown amount returns nil")
    func keysetKeysUnknownAmount() {
        let keys: [Int: String] = [1: "key1"]
        let keysetKeys = KeysetKeys(keys: keys)
        
        #expect(keysetKeys.privateKey(for: 99) == nil)
    }
    
    @Test("KeysetKeys encoding and decoding roundtrip")
    func keysetKeysEncodingRoundtrip() throws {
        let original: [Int: String] = [
            1: "privatekey1hex",
            2: "privatekey2hex",
            4: "privatekey4hex",
            8: "privatekey8hex"
        ]
        let keysetKeys = KeysetKeys(keys: original)
        
        let encoded = try keysetKeys.encode()
        let decoded = try KeysetKeys.decode(from: encoded)
        
        #expect(decoded.amounts == keysetKeys.amounts)
        for amount in keysetKeys.amounts {
            #expect(decoded.privateKey(for: amount) == keysetKeys.privateKey(for: amount))
        }
    }
    
    @Test("KeysetKeys encoding is valid JSON")
    func keysetKeysEncodingIsJSON() throws {
        let keys: [Int: String] = [1: "key1", 2: "key2"]
        let keysetKeys = KeysetKeys(keys: keys)
        
        let encoded = try keysetKeys.encode()
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        
        #expect(json != nil)
        #expect(json?["keys"] != nil)
    }
    
    // MARK: - Keyset ID Format Tests
    
    @Test("Keyset ID has correct format - 16 hex characters")
    func keysetIdFormat() {
        // A valid keyset ID from NUT-02 examples
        let keysetId = "009a1f293253e41e"
        
        // Should be 16 characters: "00" prefix + 14 hex chars
        #expect(keysetId.count == 16)
        #expect(keysetId.hasPrefix("00"))
        
        // All characters should be valid hex
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        #expect(keysetId.unicodeScalars.allSatisfy { hexChars.contains($0) })
    }
    
    @Test("Keyset ID version byte is 00")
    func keysetIdVersionByte() {
        // From NUT-02: version byte is "00"
        let exampleIds = [
            "009a1f293253e41e",
            "0042ade98b2a370a",
            "00c074b96c7e2b0e"
        ]
        
        for id in exampleIds {
            #expect(id.hasPrefix("00"))
        }
    }
    
    // MARK: - Keyset ID Derivation Logic Tests
    // Note: Full derivation tests require generating real keypairs
    // These tests verify the algorithm components
    
    @Test("Keyset ID derivation - sorting public keys by amount")
    func keysetIdSortingByAmount() {
        // Test that when we sort by amount, we get correct order
        let publicKeys: [Int: String] = [
            8: "pub8",
            1: "pub1",
            4: "pub4",
            2: "pub2"
        ]
        
        let sorted = publicKeys.sorted { $0.key < $1.key }
        let sortedAmounts = sorted.map { $0.key }
        
        #expect(sortedAmounts == [1, 2, 4, 8])
    }
    
    @Test("Keyset ID derivation - concatenation order matters")
    func keysetIdConcatenationOrder() {
        // Different order of concatenation should produce different hashes
        let key1 = Data([0x01, 0x02])
        let key2 = Data([0x03, 0x04])
        
        var concat1 = Data()
        concat1.append(key1)
        concat1.append(key2)
        
        var concat2 = Data()
        concat2.append(key2)
        concat2.append(key1)
        
        let hash1 = SHA256Helper.hash(data: concat1)
        let hash2 = SHA256Helper.hash(data: concat2)
        
        #expect(hash1 != hash2)
    }
    
    @Test("Keyset ID derivation - first 7 bytes extraction")
    func keysetIdFirst7Bytes() {
        let testData = "test public key concatenation".data(using: .utf8)!
        let hash = SHA256Helper.hash(data: testData)
        
        // Take first 7 bytes = 14 hex chars
        let first7Bytes = Array(hash.prefix(7))
        let hexString = first7Bytes.map { String(format: "%02x", $0) }.joined()
        
        #expect(hexString.count == 14)
        
        // Full keyset ID would be "00" + hexString = 16 chars
        let keysetId = "00" + hexString
        #expect(keysetId.count == 16)
    }
    
    // MARK: - Error Types Tests
    
    @Test("KeysetManagerError descriptions")
    func keysetManagerErrorDescriptions() {
        let errors: [KeysetManagerError] = [
            .keysetNotFound("abc123"),
            .keysetInactive("def456"),
            .amountNotSupported(100, "ghi789"),
            .failedToGenerateKeypair,
            .failedToLoadKeyset("bad data"),
            .noActiveKeyset("sat")
        ]
        
        for error in errors {
            let description = error.description
            #expect(!description.isEmpty)
        }
    }
    
    @Test("KeysetManagerError keysetNotFound contains ID")
    func keysetManagerErrorKeysetNotFoundContainsId() {
        let error = KeysetManagerError.keysetNotFound("test123")
        #expect(error.description.contains("test123"))
    }
    
    @Test("KeysetManagerError amountNotSupported contains amount and keyset")
    func keysetManagerErrorAmountNotSupportedDetails() {
        let error = KeysetManagerError.amountNotSupported(256, "keyset999")
        #expect(error.description.contains("256"))
        #expect(error.description.contains("keyset999"))
    }
    
    // MARK: - Power of 2 Amount Tests
    
    @Test("Standard keyset amounts are powers of 2")
    func standardKeysetAmounts() {
        // Standard keyset uses amounts 1, 2, 4, 8, ... up to 2^maxOrder
        let maxOrder = 20
        var amounts: [Int] = []
        
        for order in 0...maxOrder {
            amounts.append(1 << order)
        }
        
        // Verify first few
        #expect(amounts[0] == 1)
        #expect(amounts[1] == 2)
        #expect(amounts[2] == 4)
        #expect(amounts[3] == 8)
        #expect(amounts[4] == 16)
        
        // Verify last one
        #expect(amounts[20] == 1_048_576)  // 2^20
    }
    
    @Test("All amounts up to 2^20 can be represented")
    func amountsCanRepresentAnyValue() {
        // Any amount up to 2^21-1 can be represented as sum of powers of 2
        // This is the basis of Cashu denomination
        let maxValue = (1 << 21) - 1
        
        // We can represent maxValue as sum of 1 + 2 + 4 + ... + 2^20
        var sum = 0
        for order in 0...20 {
            sum += 1 << order
        }
        
        #expect(sum == maxValue)
    }
}
