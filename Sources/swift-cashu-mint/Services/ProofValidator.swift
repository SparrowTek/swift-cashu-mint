import Foundation
import Fluent
import CoreCashu
import P256K

/// Error types for proof validation
enum ProofValidationError: Error, CustomStringConvertible {
    case invalidSignature
    case proofAlreadySpent(String)
    case proofIsPending(String)
    case unknownKeyset(String)
    case invalidSecret(String)
    case invalidC(String)
    case amountMismatch(expected: Int, got: Int)
    case duplicateProof(String)
    
    var description: String {
        switch self {
        case .invalidSignature:
            return "Invalid proof signature"
        case .proofAlreadySpent(let y):
            return "Proof already spent: \(y)"
        case .proofIsPending(let y):
            return "Proof is pending: \(y)"
        case .unknownKeyset(let id):
            return "Unknown keyset: \(id)"
        case .invalidSecret(let reason):
            return "Invalid secret: \(reason)"
        case .invalidC(let reason):
            return "Invalid C (signature): \(reason)"
        case .amountMismatch(let expected, let got):
            return "Amount mismatch: expected \(expected), got \(got)"
        case .duplicateProof(let y):
            return "Duplicate proof in inputs: \(y)"
        }
    }
}

/// Result of validating a batch of proofs
struct ValidationResult: Sendable {
    let valid: [ProofData]
    let invalid: [(ProofData, ProofValidationError)]
    
    var isAllValid: Bool { invalid.isEmpty }
    var totalAmount: Int { valid.reduce(0) { $0 + $1.amount } }
}

/// Service for validating proofs (token signatures)
actor ProofValidator {
    private let database: Database
    private let keysetManager: KeysetManager
    
    init(database: Database, keysetManager: KeysetManager) {
        self.database = database
        self.keysetManager = keysetManager
    }
    
    // MARK: - Proof Validation
    
    /// Validate a batch of proofs
    /// Checks: signature validity, not spent, not pending, keyset exists, no duplicates
    func validateProofs(_ proofs: [ProofData]) async throws -> ValidationResult {
        var valid: [ProofData] = []
        var invalid: [(ProofData, ProofValidationError)] = []
        
        // Check for duplicates within the batch
        var seenYs: Set<String> = []
        
        for proof in proofs {
            do {
                // Compute Y = hash_to_curve(secret)
                let y = try computeY(from: proof.secret)
                let yHex = y.dataRepresentation.hexEncodedString()
                
                // Check for duplicates in this batch
                if seenYs.contains(yHex) {
                    invalid.append((proof, .duplicateProof(yHex)))
                    continue
                }
                seenYs.insert(yHex)
                
                // Check if proof is already spent
                if try await isSpent(y: yHex) {
                    invalid.append((proof, .proofAlreadySpent(yHex)))
                    continue
                }
                
                // Check if proof is pending
                if try await isPending(y: yHex) {
                    invalid.append((proof, .proofIsPending(yHex)))
                    continue
                }
                
                // Verify the signature
                try await verifySignature(proof: proof, y: y)
                
                valid.append(proof)
            } catch let error as ProofValidationError {
                invalid.append((proof, error))
            } catch {
                invalid.append((proof, .invalidSignature))
            }
        }
        
        return ValidationResult(valid: valid, invalid: invalid)
    }
    
    /// Validate a single proof
    func validateProof(_ proof: ProofData) async throws {
        // Compute Y = hash_to_curve(secret)
        let y = try computeY(from: proof.secret)
        let yHex = y.dataRepresentation.hexEncodedString()
        
        // Check if proof is already spent
        if try await isSpent(y: yHex) {
            throw ProofValidationError.proofAlreadySpent(yHex)
        }
        
        // Check if proof is pending
        if try await isPending(y: yHex) {
            throw ProofValidationError.proofIsPending(yHex)
        }
        
        // Verify the signature
        try await verifySignature(proof: proof, y: y)
    }
    
    // MARK: - Signature Verification
    
    /// Verify that the proof signature is valid
    /// Checks: k * Y == C where k is the mint's private key for this amount
    private func verifySignature(proof: ProofData, y: P256K.KeyAgreement.PublicKey) async throws {
        // Get the keyset
        let keyset: LoadedKeyset
        do {
            keyset = try await keysetManager.getKeyset(id: proof.id)
        } catch {
            throw ProofValidationError.unknownKeyset(proof.id)
        }
        
        // Get the private key for this amount
        guard let privateKey = keyset.privateKeys[proof.amount] else {
            throw ProofValidationError.amountMismatch(expected: proof.amount, got: proof.amount)
        }
        
        // Parse C (the unblinded signature)
        guard let cData = Data(hexString: proof.C) else {
            throw ProofValidationError.invalidC("Invalid hex string")
        }
        
        // Verify: k * Y == C
        let mint = Mint(privateKey: privateKey)
        let isValid = try mint.verifyToken(secret: proof.secret, signature: cData)
        
        if !isValid {
            throw ProofValidationError.invalidSignature
        }
    }
    
    // MARK: - Spent/Pending Checks
    
    /// Check if a proof is already spent
    func isSpent(y: String) async throws -> Bool {
        let count = try await SpentProof.query(on: database)
            .filter(\.$y == y)
            .count()
        return count > 0
    }
    
    /// Check if a proof is pending
    func isPending(y: String) async throws -> Bool {
        // Also check if the pending entry has expired
        let now = Date()
        let count = try await PendingProof.query(on: database)
            .filter(\.$y == y)
            .filter(\.$expiresAt > now)
            .count()
        return count > 0
    }
    
    /// Batch check spent status for multiple Y values
    func checkSpentStatus(_ ys: [String]) async throws -> [String: ProofState] {
        var results: [String: ProofState] = [:]
        
        // Initialize all as unspent
        for y in ys {
            results[y] = .unspent
        }
        
        // Check spent
        let spentProofs = try await SpentProof.query(on: database)
            .filter(\.$y ~~ ys)
            .all()
        
        for spent in spentProofs {
            results[spent.y] = .spent
        }
        
        // Check pending (only non-expired)
        let now = Date()
        let pendingProofs = try await PendingProof.query(on: database)
            .filter(\.$y ~~ ys)
            .filter(\.$expiresAt > now)
            .all()
        
        for pending in pendingProofs {
            // Only mark as pending if not already spent
            if results[pending.y] != .spent {
                results[pending.y] = .pending
            }
        }
        
        return results
    }
    
    // MARK: - Y Computation
    
    /// Compute Y = hash_to_curve(secret)
    func computeY(from secret: String) throws -> P256K.KeyAgreement.PublicKey {
        try hashToCurve(secret)
    }
    
    /// Compute Y values for a batch of proofs
    func computeYs(from proofs: [ProofData]) throws -> [(ProofData, String)] {
        try proofs.map { proof in
            let y = try computeY(from: proof.secret)
            return (proof, y.dataRepresentation.hexEncodedString())
        }
    }
}
