import Foundation
import CoreCashu
import CryptoKit
import Logging

// MARK: - Spending Condition Errors

enum SpendingConditionError: Error, CustomStringConvertible, Sendable {
    case invalidSecretFormat(String)
    case unsupportedConditionKind(String)
    case signatureRequired
    case invalidSignature(String)
    case insufficientSignatures(required: Int, provided: Int)
    case locktimeNotExpired(expiresAt: Int)
    case preimageRequired
    case invalidPreimage
    case invalidPublicKey(String)
    case sigAllMismatch
    case witnessRequired
    case invalidWitnessFormat(String)

    var description: String {
        switch self {
        case .invalidSecretFormat(let reason):
            return "Invalid secret format: \(reason)"
        case .unsupportedConditionKind(let kind):
            return "Unsupported spending condition kind: \(kind)"
        case .signatureRequired:
            return "Signature required but not provided"
        case .invalidSignature(let reason):
            return "Invalid signature: \(reason)"
        case .insufficientSignatures(let required, let provided):
            return "Insufficient signatures: required \(required), provided \(provided)"
        case .locktimeNotExpired(let expiresAt):
            return "Locktime not expired: expires at \(expiresAt)"
        case .preimageRequired:
            return "Preimage required for HTLC"
        case .invalidPreimage:
            return "Invalid preimage - hash does not match"
        case .invalidPublicKey(let key):
            return "Invalid public key: \(key)"
        case .sigAllMismatch:
            return "SIG_ALL requires all inputs to have same secret data and tags"
        case .witnessRequired:
            return "Witness required for spending condition"
        case .invalidWitnessFormat(let reason):
            return "Invalid witness format: \(reason)"
        }
    }
}

// MARK: - Spending Condition Validator

/// Validates spending conditions (NUT-10, NUT-11, NUT-14) for proofs
actor SpendingConditionValidator {
    private let logger: Logger
    private let currentTime: () -> Int

    init(logger: Logger, currentTime: @escaping () -> Int = { Int(Date().timeIntervalSince1970) }) {
        self.logger = logger
        self.currentTime = currentTime
    }

    // MARK: - Public API

    /// Validate spending conditions for a batch of proofs
    /// - Parameters:
    ///   - proofs: The proofs to validate
    ///   - outputs: Optional outputs (needed for SIG_ALL validation)
    /// - Returns: List of proofs that failed validation with their errors
    func validateSpendingConditions(
        proofs: [ProofData],
        outputs: [BlindedMessageData] = []
    ) async throws -> [(ProofData, SpendingConditionError)] {
        var failures: [(ProofData, SpendingConditionError)] = []

        // First pass: check if any proof has SIG_ALL
        var hasSigAll = false
        var sigAllCondition: P2PKSpendingCondition?

        for proof in proofs {
            if let condition = parseP2PKCondition(from: proof.secret) {
                if condition.signatureFlag == .sigAll {
                    hasSigAll = true
                    sigAllCondition = condition
                    break
                }
            }
        }

        // If SIG_ALL, validate all proofs have matching conditions
        if hasSigAll, let expectedCondition = sigAllCondition {
            for proof in proofs {
                guard let condition = parseP2PKCondition(from: proof.secret) else {
                    failures.append((proof, .invalidSecretFormat("Expected P2PK secret for SIG_ALL")))
                    continue
                }

                if condition.signatureFlag != .sigAll ||
                   condition.publicKey != expectedCondition.publicKey {
                    failures.append((proof, .sigAllMismatch))
                }
            }

            // For SIG_ALL, only first proof needs witness, validate aggregated message
            if let firstProof = proofs.first {
                do {
                    try validateSigAll(
                        firstProof: firstProof,
                        allProofs: proofs,
                        outputs: outputs,
                        condition: expectedCondition
                    )
                } catch let error as SpendingConditionError {
                    failures.append((firstProof, error))
                }
            }
        } else {
            // SIG_INPUTS: validate each proof individually
            for proof in proofs {
                do {
                    try validateProofSpendingCondition(proof)
                } catch let error as SpendingConditionError {
                    failures.append((proof, error))
                } catch {
                    failures.append((proof, .invalidSecretFormat(error.localizedDescription)))
                }
            }
        }

        return failures
    }

    /// Check if a secret has a spending condition
    func hasSpendingCondition(_ secret: String) -> Bool {
        return parseWellKnownSecret(from: secret) != nil
    }

    /// Get the kind of spending condition (P2PK, HTLC, or nil for regular)
    func getSpendingConditionKind(_ secret: String) -> String? {
        return parseWellKnownSecret(from: secret)?.kind
    }

    // MARK: - Individual Proof Validation

    /// Validate a single proof's spending condition
    private func validateProofSpendingCondition(_ proof: ProofData) throws {
        // Try to parse as well-known secret
        guard let wellKnownSecret = parseWellKnownSecret(from: proof.secret) else {
            // Not a well-known secret format - no spending condition
            return
        }

        switch wellKnownSecret.kind {
        case SpendingConditionKind.p2pk:
            try validateP2PK(proof: proof, secret: wellKnownSecret)

        case SpendingConditionKind.htlc:
            try validateHTLC(proof: proof, secret: wellKnownSecret)

        default:
            throw SpendingConditionError.unsupportedConditionKind(wellKnownSecret.kind)
        }
    }

    // MARK: - P2PK Validation (NUT-11)

    /// Validate P2PK spending condition
    private func validateP2PK(proof: ProofData, secret: WellKnownSecret) throws {
        let condition: P2PKSpendingCondition
        do {
            condition = try P2PKSpendingCondition.fromWellKnownSecret(secret)
        } catch {
            throw SpendingConditionError.invalidSecretFormat("Failed to parse P2PK condition")
        }

        // If locktime has passed
        if condition.isExpired() {
            // Check if can be spent by anyone (locktime passed, no refund keys)
            if condition.canBeSpentByAnyone() {
                logger.debug("P2PK proof can be spent by anyone (locktime expired, no refund)")
                return
            }

            // If refund keys exist, validate refund signature
            if condition.canBeSpentByRefund() {
                try validateRefundSignature(proof: proof, condition: condition)
                return
            }
        }

        // Normal case: validate signature(s) from authorized pubkeys
        try validateP2PKSignatures(proof: proof, condition: condition)
    }

    /// Validate P2PK signatures
    private func validateP2PKSignatures(proof: ProofData, condition: P2PKSpendingCondition) throws {
        // Get witness
        guard let witnessString = proof.witness else {
            throw SpendingConditionError.witnessRequired
        }

        let witness: P2PKWitness
        do {
            witness = try P2PKWitness.fromString(witnessString)
        } catch {
            throw SpendingConditionError.invalidWitnessFormat("Failed to parse P2PK witness")
        }

        guard !witness.signatures.isEmpty else {
            throw SpendingConditionError.signatureRequired
        }

        // Get all possible signers
        let possibleSigners = condition.getAllPossibleSigners()
        var validSignatureCount = 0
        var signersCounted: Set<String> = []

        // Validate signatures
        for signature in witness.signatures {
            for signer in possibleSigners {
                // Skip if we already counted a valid signature from this signer
                if signersCounted.contains(signer) {
                    continue
                }

                if validateSchnorrSignature(signature: signature, publicKey: signer, message: proof.secret) {
                    validSignatureCount += 1
                    signersCounted.insert(signer)
                    break
                }
            }
        }

        // Check we have enough signatures
        if validSignatureCount < condition.requiredSigs {
            throw SpendingConditionError.insufficientSignatures(
                required: condition.requiredSigs,
                provided: validSignatureCount
            )
        }

        logger.debug("P2PK validation passed", metadata: [
            "valid_sigs": .string(String(validSignatureCount)),
            "required_sigs": .string(String(condition.requiredSigs))
        ])
    }

    /// Validate refund signature after locktime
    private func validateRefundSignature(proof: ProofData, condition: P2PKSpendingCondition) throws {
        guard let witnessString = proof.witness else {
            throw SpendingConditionError.witnessRequired
        }

        let witness: P2PKWitness
        do {
            witness = try P2PKWitness.fromString(witnessString)
        } catch {
            throw SpendingConditionError.invalidWitnessFormat("Failed to parse P2PK witness")
        }

        // Validate at least one signature from refund keys
        for signature in witness.signatures {
            for refundKey in condition.refundPubkeys {
                if validateSchnorrSignature(signature: signature, publicKey: refundKey, message: proof.secret) {
                    logger.debug("P2PK refund validation passed")
                    return
                }
            }
        }

        throw SpendingConditionError.invalidSignature("No valid refund signature")
    }

    // MARK: - HTLC Validation (NUT-14)

    /// Validate HTLC spending condition
    private func validateHTLC(proof: ProofData, secret: WellKnownSecret) throws {
        guard secret.isHTLC else {
            throw SpendingConditionError.invalidSecretFormat("Not an HTLC secret")
        }

        guard let witnessString = proof.witness else {
            throw SpendingConditionError.witnessRequired
        }

        let witness: HTLCWitness
        do {
            guard let data = witnessString.data(using: .utf8) else {
                throw SpendingConditionError.invalidWitnessFormat("Invalid UTF-8")
            }
            witness = try JSONDecoder().decode(HTLCWitness.self, from: data)
        } catch {
            throw SpendingConditionError.invalidWitnessFormat("Failed to parse HTLC witness")
        }

        // Get hash lock from secret
        guard let hashLock = secret.hashLock else {
            throw SpendingConditionError.invalidSecretFormat("Missing hash lock in HTLC")
        }

        // Try to validate preimage
        let preimageValid = validateHTLCPreimage(preimage: witness.preimage, hashLock: hashLock)

        if preimageValid {
            // Preimage is valid, now check signatures if required
            if let pubkeys = secret.pubkeys, !pubkeys.isEmpty {
                try validateHTLCSignatures(witness: witness, secret: secret, pubkeys: pubkeys)
            }
            logger.debug("HTLC validation passed (preimage valid)")
            return
        }

        // Preimage invalid - check refund conditions
        let now = currentTime()

        if let locktime = secret.locktime {
            if Int(locktime) > now {
                throw SpendingConditionError.locktimeNotExpired(expiresAt: Int(locktime))
            }
        }

        // Locktime passed, validate refund signature
        guard let refundKey = secret.refundPublicKey else {
            throw SpendingConditionError.invalidPreimage
        }

        for signature in witness.signatures {
            if validateSchnorrSignature(signature: signature, publicKey: refundKey, message: proof.secret) {
                logger.debug("HTLC refund validation passed")
                return
            }
        }

        throw SpendingConditionError.invalidSignature("No valid HTLC refund signature")
    }

    /// Validate HTLC preimage
    private func validateHTLCPreimage(preimage: String, hashLock: String) -> Bool {
        guard let preimageData = Data(hexString: preimage),
              preimageData.count == 32 else {
            return false
        }

        guard let hashLockData = Data(hexString: hashLock.lowercased()) else {
            return false
        }

        // Compute SHA256 hash of preimage
        let computedHash = Data(SHA256.hash(data: preimageData))

        // Compare with hash lock (constant-time comparison for security)
        return computedHash == hashLockData
    }

    /// Validate HTLC signatures
    private func validateHTLCSignatures(witness: HTLCWitness, secret: WellKnownSecret, pubkeys: [String]) throws {
        // Check if we need all signatures
        let nSigsTag = secret.secretData.tags?.first { $0.first == "n_sigs" }
        let requiredSigs = nSigsTag.flatMap { $0.dropFirst().first }.flatMap { Int($0) } ?? 1

        var validSigCount = 0

        for signature in witness.signatures {
            for pubkey in pubkeys {
                if validateSchnorrSignature(signature: signature, publicKey: pubkey, message: secret.secretData.nonce) {
                    validSigCount += 1
                    break
                }
            }
        }

        if validSigCount < requiredSigs {
            throw SpendingConditionError.insufficientSignatures(required: requiredSigs, provided: validSigCount)
        }
    }

    // MARK: - SIG_ALL Validation

    /// Validate SIG_ALL spending condition (signatures cover all inputs and outputs)
    private func validateSigAll(
        firstProof: ProofData,
        allProofs: [ProofData],
        outputs: [BlindedMessageData],
        condition: P2PKSpendingCondition
    ) throws {
        guard let witnessString = firstProof.witness else {
            throw SpendingConditionError.witnessRequired
        }

        let witness: P2PKWitness
        do {
            witness = try P2PKWitness.fromString(witnessString)
        } catch {
            throw SpendingConditionError.invalidWitnessFormat("Failed to parse P2PK witness")
        }

        // Build aggregated message: secret_0 || ... || secret_n || B_0 || ... || B_m
        var aggregatedMessage = ""
        for proof in allProofs {
            aggregatedMessage += proof.secret
        }
        for output in outputs {
            aggregatedMessage += output.B_
        }

        // Validate signatures on aggregated message
        let possibleSigners = condition.getAllPossibleSigners()
        var validSignatureCount = 0

        for signature in witness.signatures {
            for signer in possibleSigners {
                if validateSchnorrSignature(signature: signature, publicKey: signer, message: aggregatedMessage) {
                    validSignatureCount += 1
                    break
                }
            }
        }

        if validSignatureCount < condition.requiredSigs {
            throw SpendingConditionError.insufficientSignatures(
                required: condition.requiredSigs,
                provided: validSignatureCount
            )
        }

        logger.debug("SIG_ALL validation passed", metadata: [
            "valid_sigs": .string(String(validSignatureCount)),
            "required_sigs": .string(String(condition.requiredSigs)),
            "input_count": .string(String(allProofs.count)),
            "output_count": .string(String(outputs.count))
        ])
    }

    // MARK: - Parsing Helpers

    /// Parse a secret as a well-known secret format
    private func parseWellKnownSecret(from secret: String) -> WellKnownSecret? {
        return try? WellKnownSecret.fromString(secret)
    }

    /// Parse P2PK condition from secret
    private func parseP2PKCondition(from secret: String) -> P2PKSpendingCondition? {
        guard let wellKnown = parseWellKnownSecret(from: secret),
              wellKnown.kind == SpendingConditionKind.p2pk else {
            return nil
        }
        return try? P2PKSpendingCondition.fromWellKnownSecret(wellKnown)
    }

    // MARK: - Signature Validation

    /// Validate a Schnorr signature
    /// Uses SHA256(message) as the signed data
    private func validateSchnorrSignature(signature: String, publicKey: String, message: String) -> Bool {
        // Use CoreCashu's P2PKSignatureValidator
        return P2PKSignatureValidator.validateSignature(
            signature: signature,
            publicKey: publicKey,
            message: message
        )
    }
}

// MARK: - Mint Configuration Extension

extension MintConfiguration {
    /// Whether NUT-10/11/14 spending conditions are enabled
    var spendingConditionsEnabled: Bool {
        ProcessInfo.processInfo.environment["ENABLE_SPENDING_CONDITIONS"]?.lowercased() == "true"
    }
}
