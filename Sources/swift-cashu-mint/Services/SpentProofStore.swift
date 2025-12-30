import Foundation
import Fluent
import CoreCashu
import P256K

/// Error types for spent proof operations
enum SpentProofError: Error, CustomStringConvertible {
    case doubleSpendAttempt([String])
    case databaseError(String)
    case proofNotFound(String)
    
    var description: String {
        switch self {
        case .doubleSpendAttempt(let ys):
            return "Double-spend attempt detected for proofs: \(ys.joined(separator: ", "))"
        case .databaseError(let reason):
            return "Database error: \(reason)"
        case .proofNotFound(let y):
            return "Proof not found: \(y)"
        }
    }
}

/// Service for tracking spent proofs (double-spend prevention)
/// This is the CRITICAL service for preventing double-spending
actor SpentProofStore {
    private let database: Database
    
    init(database: Database) {
        self.database = database
    }
    
    // MARK: - Mark Proofs as Spent
    
    /// Mark a batch of proofs as spent atomically
    /// Returns true if all proofs were successfully marked as spent
    /// Returns false if any proof was already spent (rolls back all)
    func markAsSpent(_ proofs: [ProofData], witness: String? = nil) async throws -> Bool {
        // Compute Y values for all proofs
        var yValues: [(ProofData, String)] = []
        for proof in proofs {
            let y = try hashToCurve(proof.secret)
            yValues.append((proof, y.dataRepresentation.hexEncodedString()))
        }
        
        // Check if any are already spent (before starting transaction)
        let existingYs = yValues.map { $0.1 }
        let alreadySpent = try await checkAlreadySpent(existingYs)
        
        if !alreadySpent.isEmpty {
            throw SpentProofError.doubleSpendAttempt(alreadySpent)
        }
        
        // Use database transaction for atomicity
        // Capture values before the closure to avoid Sendable issues
        let entries = yValues.map { (proof, yHex) in
            (y: yHex, keysetId: proof.id, amount: proof.amount, witness: witness ?? proof.witness)
        }
        
        do {
            try await database.transaction { transaction in
                for entry in entries {
                    let spentProof = SpentProof(
                        y: entry.y,
                        keysetId: entry.keysetId,
                        amount: entry.amount,
                        witness: entry.witness
                    )
                    try await spentProof.save(on: transaction)
                }
            }
            return true
        } catch {
            // If we get a unique constraint violation, it's a double-spend attempt
            // that happened between our check and insert (race condition)
            if error.localizedDescription.contains("unique") ||
               error.localizedDescription.contains("duplicate") {
                throw SpentProofError.doubleSpendAttempt(existingYs)
            }
            throw SpentProofError.databaseError(error.localizedDescription)
        }
    }
    
    /// Mark a single proof as spent
    func markAsSpent(_ proof: ProofData, witness: String? = nil) async throws -> Bool {
        return try await markAsSpent([proof], witness: witness)
    }
    
    /// Mark proofs as spent by Y values directly (used after validation)
    func markAsSpentByY(_ entries: [(y: String, keysetId: String, amount: Int, witness: String?)]) async throws -> Bool {
        // Check if any are already spent
        let existingYs = entries.map { $0.y }
        let alreadySpent = try await checkAlreadySpent(existingYs)
        
        if !alreadySpent.isEmpty {
            throw SpentProofError.doubleSpendAttempt(alreadySpent)
        }
        
        // Use database transaction for atomicity
        do {
            try await database.transaction { transaction in
                for entry in entries {
                    let spentProof = SpentProof(
                        y: entry.y,
                        keysetId: entry.keysetId,
                        amount: entry.amount,
                        witness: entry.witness
                    )
                    try await spentProof.save(on: transaction)
                }
            }
            return true
        } catch {
            if error.localizedDescription.contains("unique") ||
               error.localizedDescription.contains("duplicate") {
                throw SpentProofError.doubleSpendAttempt(existingYs)
            }
            throw SpentProofError.databaseError(error.localizedDescription)
        }
    }
    
    // MARK: - Check Spent Status
    
    /// Check if a proof is spent by its Y value
    func isSpent(y: String) async throws -> Bool {
        let count = try await SpentProof.query(on: database)
            .filter(\.$y == y)
            .count()
        return count > 0
    }
    
    /// Check which Y values are already spent
    private func checkAlreadySpent(_ ys: [String]) async throws -> [String] {
        let spentProofs = try await SpentProof.query(on: database)
            .filter(\.$y ~~ ys)
            .all()
        return spentProofs.map { $0.y }
    }
    
    /// Get the witness for a spent proof
    func getWitness(y: String) async throws -> String? {
        let spentProof = try await SpentProof.query(on: database)
            .filter(\.$y == y)
            .first()
        return spentProof?.witness
    }
    
    /// Get spent proof details for NUT-07 response
    func getSpentProofStates(_ ys: [String]) async throws -> [ProofStateResponse] {
        var results: [ProofStateResponse] = []
        
        let spentProofs = try await SpentProof.query(on: database)
            .filter(\.$y ~~ ys)
            .all()
        
        let spentMap = Dictionary(uniqueKeysWithValues: spentProofs.map { ($0.y, $0) })
        
        for y in ys {
            if let spent = spentMap[y] {
                results.append(ProofStateResponse(
                    y: y,
                    state: .spent,
                    witness: spent.witness
                ))
            } else {
                results.append(ProofStateResponse(
                    y: y,
                    state: .unspent,
                    witness: nil
                ))
            }
        }
        
        return results
    }
    
    // MARK: - Pending Proofs Management
    
    /// Mark proofs as pending (in-flight, e.g., during melt operation)
    func markAsPending(_ proofs: [ProofData], quoteId: String?, expiresAt: Date) async throws {
        // Compute Y values and save individually
        // Note: For better atomicity, this should use a transaction,
        // but Swift 6 concurrency makes this challenging with Fluent
        for proof in proofs {
            let y = try hashToCurve(proof.secret)
            let pendingProof = PendingProof(
                y: y.dataRepresentation.hexEncodedString(),
                keysetId: proof.id,
                amount: proof.amount,
                quoteId: quoteId,
                expiresAt: expiresAt
            )
            try await pendingProof.save(on: database)
        }
    }
    
    /// Remove proofs from pending (after operation completes or fails)
    func removePending(ys: [String]) async throws {
        try await PendingProof.query(on: database)
            .filter(\.$y ~~ ys)
            .delete()
    }
    
    /// Remove pending proofs for a specific quote
    func removePending(forQuote quoteId: String) async throws {
        try await PendingProof.query(on: database)
            .filter(\.$quoteId == quoteId)
            .delete()
    }
    
    /// Clean up expired pending proofs
    func cleanupExpiredPending() async throws -> Int {
        let now = Date()
        let expired = try await PendingProof.query(on: database)
            .filter(\.$expiresAt < now)
            .all()
        
        let count = expired.count
        
        for pending in expired {
            try await pending.delete(on: database)
        }
        
        return count
    }
    
    /// Move proofs from pending to spent (after successful melt)
    func movePendingToSpent(ys: [String], witness: String? = nil) async throws {
        try await database.transaction { transaction in
            // Get pending proofs
            let pendingProofs = try await PendingProof.query(on: transaction)
                .filter(\.$y ~~ ys)
                .all()
            
            // Create spent proof records
            for pending in pendingProofs {
                let spentProof = SpentProof(
                    y: pending.y,
                    keysetId: pending.keysetId,
                    amount: pending.amount,
                    witness: witness
                )
                try await spentProof.save(on: transaction)
            }
            
            // Delete pending records
            try await PendingProof.query(on: transaction)
                .filter(\.$y ~~ ys)
                .delete()
        }
    }
}
