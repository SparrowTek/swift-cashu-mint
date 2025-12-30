import Foundation
import Fluent
import CoreCashu
@preconcurrency import P256K

/// Error types for signing operations
enum SigningError: Error, CustomStringConvertible {
    case invalidBlindedMessage(String)
    case signingFailed(String)
    case keysetNotActive(String)
    case invalidKeysetId(String)
    
    var description: String {
        switch self {
        case .invalidBlindedMessage(let reason):
            return "Invalid blinded message: \(reason)"
        case .signingFailed(let reason):
            return "Signing failed: \(reason)"
        case .keysetNotActive(let id):
            return "Keyset is not active: \(id)"
        case .invalidKeysetId(let id):
            return "Invalid keyset ID: \(id)"
        }
    }
}

/// Service for BDHKE blind signing operations
/// Signs blinded messages from wallets and stores signatures for NUT-09 restore
actor SigningService {
    private let database: Database
    private let keysetManager: KeysetManager
    
    init(database: Database, keysetManager: KeysetManager) {
        self.database = database
        self.keysetManager = keysetManager
    }
    
    // MARK: - Blind Signing
    
    /// Sign a batch of blinded messages
    /// Returns blind signatures in the same order as inputs
    func signBlindedMessages(_ messages: [BlindedMessageData]) async throws -> [BlindSignatureData] {
        var signatures: [BlindSignatureData] = []
        
        for message in messages {
            let signature = try await signBlindedMessage(message)
            signatures.append(signature)
        }
        
        return signatures
    }
    
    /// Sign a single blinded message
    func signBlindedMessage(_ message: BlindedMessageData) async throws -> BlindSignatureData {
        // Validate keyset exists and is active
        let keyset = try await keysetManager.getKeyset(id: message.id)
        
        guard keyset.active else {
            throw SigningError.keysetNotActive(message.id)
        }
        
        // Get the private key for this amount
        let privateKey = try await keysetManager.getPrivateKey(keysetId: message.id, amount: message.amount)
        
        // Parse the blinded message (B_)
        guard let blindedMessageData = Data(hexString: message.B_) else {
            throw SigningError.invalidBlindedMessage("Invalid hex string for B_")
        }
        
        // Perform BDHKE signing: C_ = k * B_
        let mint = Mint(privateKey: privateKey)
        let blindedSignatureData: Data
        do {
            blindedSignatureData = try mint.signBlindedMessage(blindedMessageData)
        } catch {
            throw SigningError.signingFailed(error.localizedDescription)
        }
        
        let blindedSignatureHex = blindedSignatureData.hexEncodedString()
        
        // Store the blind signature for NUT-09 restore
        let record = BlindSignatureRecord(
            B_: message.B_,
            keysetId: message.id,
            amount: message.amount,
            C_: blindedSignatureHex
        )
        try await record.save(on: database)
        
        return BlindSignatureData(
            amount: message.amount,
            id: message.id,
            C_: blindedSignatureHex,
            dleq: nil  // DLEQ proofs can be added later (NUT-12)
        )
    }
    
    /// Sign blinded messages with DLEQ proofs (NUT-12)
    func signBlindedMessagesWithDLEQ(_ messages: [BlindedMessageData]) async throws -> [BlindSignatureData] {
        var signatures: [BlindSignatureData] = []
        
        for message in messages {
            let signature = try await signBlindedMessageWithDLEQ(message)
            signatures.append(signature)
        }
        
        return signatures
    }
    
    /// Sign a single blinded message with DLEQ proof
    func signBlindedMessageWithDLEQ(_ message: BlindedMessageData) async throws -> BlindSignatureData {
        // Validate keyset exists and is active
        let keyset = try await keysetManager.getKeyset(id: message.id)
        
        guard keyset.active else {
            throw SigningError.keysetNotActive(message.id)
        }
        
        // Get the private key for this amount
        let privateKey = try await keysetManager.getPrivateKey(keysetId: message.id, amount: message.amount)
        
        // Parse the blinded message (B_)
        guard let blindedMessageData = Data(hexString: message.B_) else {
            throw SigningError.invalidBlindedMessage("Invalid hex string for B_")
        }
        
        // Perform BDHKE signing: C_ = k * B_
        let mint = Mint(privateKey: privateKey)
        let blindedSignatureData: Data
        do {
            blindedSignatureData = try mint.signBlindedMessage(blindedMessageData)
        } catch {
            throw SigningError.signingFailed(error.localizedDescription)
        }
        
        let blindedSignatureHex = blindedSignatureData.hexEncodedString()
        
        // Generate DLEQ proof
        // Note: DLEQ proof generation requires accessing the DLEQProof type from CoreCashu
        // For now, we skip DLEQ generation - it can be added in a future enhancement
        let dleqProof: DLEQProofData? = nil
        // TODO: Implement DLEQ proof generation using CoreCashu's generateDLEQProof function
        
        // Store the blind signature for NUT-09 restore
        let record = BlindSignatureRecord(
            B_: message.B_,
            keysetId: message.id,
            amount: message.amount,
            C_: blindedSignatureHex,
            dleqE: dleqProof?.e,
            dleqS: dleqProof?.s
        )
        try await record.save(on: database)
        
        return BlindSignatureData(
            amount: message.amount,
            id: message.id,
            C_: blindedSignatureHex,
            dleq: dleqProof
        )
    }
    
    // MARK: - NUT-09 Restore
    
    /// Look up stored signatures for restore requests
    func getStoredSignatures(for blindedMessages: [BlindedMessageData]) async throws -> ([BlindedMessageData], [BlindSignatureData]) {
        var foundMessages: [BlindedMessageData] = []
        var foundSignatures: [BlindSignatureData] = []
        
        for message in blindedMessages {
            if let record = try await BlindSignatureRecord.query(on: database)
                .filter(\.$B_ == message.B_)
                .first() {
                foundMessages.append(message)
                foundSignatures.append(record.toBlindSignatureData())
            }
        }
        
        return (foundMessages, foundSignatures)
    }
}
