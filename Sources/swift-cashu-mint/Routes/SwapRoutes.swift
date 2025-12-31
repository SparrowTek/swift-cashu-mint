import Foundation
import Hummingbird
import Logging

// MARK: - Swap Routes (NUT-03)

/// Add swap routes to the router
/// POST /v1/swap - Exchange proofs for new signatures
func addSwapRoutes<Context: RequestContext>(
    to router: Router<Context>,
    keysetManager: KeysetManager,
    signingService: SigningService,
    proofValidator: ProofValidator,
    spentProofStore: SpentProofStore,
    feeCalculator: FeeCalculator,
    logger: Logger
) {
    router.post("/v1/swap") { request, context in
        // Decode request
        let swapRequest = try await request.decode(as: SwapRequest.self, context: context)
        
        return try await processSwap(
            request: swapRequest,
            keysetManager: keysetManager,
            signingService: signingService,
            proofValidator: proofValidator,
            spentProofStore: spentProofStore,
            feeCalculator: feeCalculator,
            logger: logger
        )
    }
}

// MARK: - POST /v1/swap (NUT-03)

/// Process a swap request: validate inputs, mark spent, sign outputs
private func processSwap(
    request: SwapRequest,
    keysetManager: KeysetManager,
    signingService: SigningService,
    proofValidator: ProofValidator,
    spentProofStore: SpentProofStore,
    feeCalculator: FeeCalculator,
    logger: Logger
) async throws -> SwapResponse {
    let inputs = request.inputs
    let outputs = request.outputs
    
    // 1. Basic validation
    guard !inputs.isEmpty else {
        throw CashuMintError.transactionNotBalanced(0, outputs.reduce(0) { $0 + $1.amount })
    }

    guard !outputs.isEmpty else {
        throw CashuMintError.transactionNotBalanced(inputs.reduce(0) { $0 + $1.amount }, 0)
    }

    // 1.5. Input format validation (hex, public keys, amounts)
    do {
        try InputValidator.validateProofsFormat(inputs)
        try InputValidator.validateBlindedMessagesFormat(outputs)
    } catch let error as ValidationError {
        throw CashuMintError.from(error)
    }
    
    // 2. Check for duplicate inputs
    let inputSecrets = Set(inputs.map { $0.secret })
    if inputSecrets.count != inputs.count {
        throw CashuMintError.duplicateInputs
    }
    
    // 3. Check for duplicate outputs
    let outputBlinds = Set(outputs.map { $0.B_ })
    if outputBlinds.count != outputs.count {
        throw CashuMintError.duplicateOutputs
    }
    
    // 4. Verify all inputs use the same unit (via keyset)
    let inputKeysetIds = Set(inputs.map { $0.id })
    var inputKeysets: [String: LoadedKeyset] = [:]
    var inputUnits: Set<String> = []
    
    for keysetId in inputKeysetIds {
        do {
            let keyset = try await keysetManager.getKeyset(id: keysetId)
            inputKeysets[keysetId] = keyset
            inputUnits.insert(keyset.unit)
        } catch {
            throw CashuMintError.keysetUnknown(keysetId)
        }
    }
    
    if inputUnits.count > 1 {
        throw CashuMintError.multipleUnits
    }
    
    let inputUnit = inputUnits.first!
    
    // 5. Verify all outputs use active keysets with the same unit
    let outputKeysetIds = Set(outputs.map { $0.id })
    var outputUnits: Set<String> = []
    
    for keysetId in outputKeysetIds {
        do {
            let keyset = try await keysetManager.getKeyset(id: keysetId)
            
            // Outputs must use active keysets
            if !keyset.active {
                throw CashuMintError.keysetInactive(keysetId)
            }
            
            outputUnits.insert(keyset.unit)
        } catch is KeysetManagerError {
            throw CashuMintError.keysetUnknown(keysetId)
        }
    }
    
    if outputUnits.count > 1 {
        throw CashuMintError.multipleUnits
    }
    
    // 6. Check input and output units match
    let outputUnit = outputUnits.first!
    if inputUnit != outputUnit {
        throw CashuMintError.inputOutputUnitMismatch
    }
    
    // 7. Calculate fees
    let fees = feeCalculator.calculateInputFees(proofs: inputs, keysets: inputKeysets)
    
    // 8. Validate transaction balance: sum(inputs) - fees == sum(outputs)
    let inputSum = inputs.reduce(0) { $0 + $1.amount }
    let outputSum = outputs.reduce(0) { $0 + $1.amount }
    
    if inputSum - fees != outputSum {
        throw CashuMintError.transactionNotBalanced(inputSum, outputSum)
    }
    
    // 9. Validate all input proofs (signatures, not spent, not pending)
    let validationResult = try await proofValidator.validateProofs(inputs)
    
    if !validationResult.isAllValid {
        // Return first error
        if let (_, error) = validationResult.invalid.first {
            switch error {
            case .proofAlreadySpent:
                throw CashuMintError.tokenAlreadySpent
            case .proofIsPending:
                throw CashuMintError.tokenAlreadySpent  // Treat pending as spent for clients
            case .invalidSignature:
                throw CashuMintError.tokenCouldNotBeVerified("Invalid signature")
            case .unknownKeyset(let id):
                throw CashuMintError.keysetUnknown(id)
            case .invalidSecret(let reason):
                throw CashuMintError.tokenCouldNotBeVerified(reason)
            case .invalidC(let reason):
                throw CashuMintError.tokenCouldNotBeVerified(reason)
            case .duplicateProof:
                throw CashuMintError.duplicateInputs
            default:
                throw CashuMintError.tokenCouldNotBeVerified(error.description)
            }
        }
    }
    
    // 10. Mark input proofs as spent (atomic operation)
    do {
        _ = try await spentProofStore.markAsSpent(inputs)
    } catch is SpentProofError {
        // Double-spend attempt detected during marking
        throw CashuMintError.tokenAlreadySpent
    }
    
    // 11. Sign all output blinded messages
    let signatures: [BlindSignatureData]
    do {
        signatures = try await signingService.signBlindedMessages(outputs)
    } catch let error as SigningError {
        // If signing fails after we marked inputs as spent, this is a serious error
        // In production, we might want to roll back the spent marking
        // For now, log and rethrow
        logger.error("Signing failed after marking inputs as spent: \(error.description)")
        throw CashuMintError.internalError("Signing failed: \(error.description)")
    }
    
    logger.info("Swap completed", metadata: [
        "input_count": .stringConvertible(inputs.count),
        "output_count": .stringConvertible(outputs.count),
        "input_sum": .stringConvertible(inputSum),
        "output_sum": .stringConvertible(outputSum),
        "fees": .stringConvertible(fees)
    ])
    
    return SwapResponse(signatures: signatures)
}
