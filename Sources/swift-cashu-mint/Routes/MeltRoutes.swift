import Foundation
import Hummingbird
import Logging

// MARK: - Melt Routes (NUT-05, NUT-08, NUT-23)

/// Add melt routes to the router
/// - POST /v1/melt/quote/bolt11 - Request a melt quote
/// - GET /v1/melt/quote/bolt11/{quote_id} - Check melt quote status
/// - POST /v1/melt/bolt11 - Melt tokens (pay Lightning invoice)
func addMeltRoutes<Context: RequestContext>(
    to router: Router<Context>,
    keysetManager: KeysetManager,
    signingService: SigningService,
    proofValidator: ProofValidator,
    spentProofStore: SpentProofStore,
    quoteManager: QuoteManager,
    feeCalculator: FeeCalculator,
    spendingConditionValidator: SpendingConditionValidator,
    lightningBackend: any LightningBackend,
    config: MintConfiguration,
    logger: Logger
) {
    // POST /v1/melt/quote/bolt11 - Request a melt quote (NUT-05, NUT-23)
    router.post("/v1/melt/quote/bolt11") { request, context in
        let quoteRequest = try await request.decode(as: MeltQuoteRequest.self, context: context)
        
        return try await createMeltQuote(
            request: quoteRequest,
            quoteManager: quoteManager,
            lightningBackend: lightningBackend,
            feeCalculator: feeCalculator,
            config: config,
            logger: logger
        )
    }
    
    // GET /v1/melt/quote/bolt11/{quote_id} - Check melt quote status (NUT-05)
    router.get("/v1/melt/quote/bolt11/{quote_id}") { request, context in
        let quoteId = context.parameters.get("quote_id") ?? ""

        // Validate quote ID format
        do {
            try InputValidator.validateQuoteId(quoteId)
        } catch {
            throw CashuMintError.quoteNotFound(quoteId)
        }

        return try await checkMeltQuote(
            quoteId: quoteId,
            quoteManager: quoteManager,
            logger: logger
        )
    }
    
    // POST /v1/melt/bolt11 - Melt tokens (NUT-05, NUT-08, NUT-23)
    router.post("/v1/melt/bolt11") { request, context in
        let meltRequest = try await request.decode(as: MeltRequest.self, context: context)

        return try await meltTokens(
            request: meltRequest,
            keysetManager: keysetManager,
            signingService: signingService,
            proofValidator: proofValidator,
            spentProofStore: spentProofStore,
            quoteManager: quoteManager,
            feeCalculator: feeCalculator,
            spendingConditionValidator: spendingConditionValidator,
            lightningBackend: lightningBackend,
            config: config,
            logger: logger
        )
    }
}

// MARK: - POST /v1/melt/quote/bolt11 (NUT-05, NUT-23)

/// Create a melt quote by decoding the Lightning invoice
/// Supports NUT-15 MPP (multi-path payments) via the options parameter
private func createMeltQuote(
    request: MeltQuoteRequest,
    quoteManager: QuoteManager,
    lightningBackend: any LightningBackend,
    feeCalculator: FeeCalculator,
    config: MintConfiguration,
    logger: Logger
) async throws -> MeltQuoteResponse {
    // 1. Validate unit
    if request.unit != config.unit {
        throw CashuMintError.unitNotSupported(request.unit)
    }

    // 2. Decode the Lightning invoice
    let decodedInvoice: DecodedInvoice
    do {
        decodedInvoice = try await lightningBackend.decodeInvoice(bolt11: request.request)
    } catch {
        throw CashuMintError.internalError("Failed to decode invoice: \(error)")
    }

    // 3. Get the invoice amount
    guard let invoiceAmountSat = decodedInvoice.amountSat else {
        // Amountless invoices not supported in V1
        throw CashuMintError.amountlessNotSupported
    }

    // 4. Handle MPP (NUT-15) - use partial amount if specified
    let mppAmountMsat = request.options?.mpp?.amount
    let amountSat: Int

    if let mppMsat = mppAmountMsat {
        // MPP: use the specified partial amount (convert from msat to sat)
        amountSat = mppMsat / 1000

        // Validate MPP amount doesn't exceed invoice amount
        if amountSat > invoiceAmountSat {
            throw CashuMintError.amountOutsideLimit(amountSat, 1, invoiceAmountSat)
        }

        // Validate MPP amount is positive
        if amountSat <= 0 {
            throw CashuMintError.amountOutsideLimit(amountSat, 1, invoiceAmountSat)
        }

        logger.info("MPP melt quote", metadata: [
            "partial_amount_sat": .string(String(amountSat)),
            "invoice_amount_sat": .string(String(invoiceAmountSat))
        ])
    } else {
        // Standard: use full invoice amount
        amountSat = invoiceAmountSat
    }

    // 5. Validate amount within limits
    if amountSat < config.meltMinAmount || amountSat > config.meltMaxAmount {
        throw CashuMintError.amountOutsideLimit(amountSat, config.meltMinAmount, config.meltMaxAmount)
    }

    // 6. Estimate fee reserve
    // Simple estimation: 1% of amount + 1 sat base fee, minimum 1 sat
    let feeReserve = feeCalculator.estimateFeeReserve(amount: amountSat, baseFee: 1, feeRate: 0.01)

    // 7. Create quote in database
    let quote = try await quoteManager.createMeltQuote(
        request: request.request,
        unit: request.unit,
        amount: amountSat,
        feeReserve: feeReserve,
        expiry: decodedInvoice.expiry,
        mppAmount: mppAmountMsat
    )

    logger.info("Melt quote created", metadata: [
        "quote_id": .string(quote.quoteId),
        "amount": .string(String(amountSat)),
        "fee_reserve": .string(String(feeReserve)),
        "unit": .string(request.unit),
        "is_mpp": .string(String(mppAmountMsat != nil))
    ])

    return MeltQuoteResponse(from: quote)
}

// MARK: - GET /v1/melt/quote/bolt11/{quote_id} (NUT-05)

/// Check melt quote status
private func checkMeltQuote(
    quoteId: String,
    quoteManager: QuoteManager,
    logger: Logger
) async throws -> MeltQuoteResponse {
    let quote: MeltQuote
    do {
        quote = try await quoteManager.getMeltQuote(id: quoteId)
    } catch is QuoteError {
        throw CashuMintError.quoteNotFound(quoteId)
    }
    
    // Check if expired
    if quote.expiry < Date() && quote.state == .unpaid {
        throw CashuMintError.quoteExpired
    }
    
    return MeltQuoteResponse(from: quote)
}

// MARK: - POST /v1/melt/bolt11 (NUT-05, NUT-08, NUT-23)

/// Melt tokens by paying a Lightning invoice
private func meltTokens(
    request: MeltRequest,
    keysetManager: KeysetManager,
    signingService: SigningService,
    proofValidator: ProofValidator,
    spentProofStore: SpentProofStore,
    quoteManager: QuoteManager,
    feeCalculator: FeeCalculator,
    spendingConditionValidator: SpendingConditionValidator,
    lightningBackend: any LightningBackend,
    config: MintConfiguration,
    logger: Logger
) async throws -> MeltQuoteResponse {
    let quoteId = request.quote
    let inputs = request.inputs
    let blankOutputs = request.outputs ?? []
    
    // 1. Get and validate quote
    let quote: MeltQuote
    do {
        quote = try await quoteManager.validateMeltQuoteForMelting(id: quoteId)
    } catch let error as QuoteError {
        switch error {
        case .quoteNotFound:
            throw CashuMintError.quoteNotFound(quoteId)
        case .quoteExpired:
            throw CashuMintError.quoteExpired
        case .quotePending:
            throw CashuMintError.quotePending
        case .quoteAlreadyPaid:
            throw CashuMintError.invoiceAlreadyPaid
        default:
            throw CashuMintError.internalError(error.description)
        }
    }
    
    // 2. Validate inputs not empty
    guard !inputs.isEmpty else {
        throw CashuMintError.transactionNotBalanced(0, quote.amount + quote.feeReserve)
    }

    // 2.5. Validate input formats
    do {
        try InputValidator.validateProofsFormat(inputs)
        if !blankOutputs.isEmpty {
            try InputValidator.validateBlindedMessagesFormat(blankOutputs)
        }
    } catch let error as ValidationError {
        throw CashuMintError.from(error)
    }

    // 2.6. Validate spending conditions (NUT-10, NUT-11, NUT-14)
    // For melt with SIG_ALL, we include the quote_id in the message
    let spendingConditionFailures = try await spendingConditionValidator.validateSpendingConditions(
        proofs: inputs,
        outputs: blankOutputs
    )
    if let (_, error) = spendingConditionFailures.first {
        throw CashuMintError.tokenCouldNotBeVerified(error.description)
    }

    // 3. Check for duplicate inputs
    let inputSecrets = Set(inputs.map { $0.secret })
    if inputSecrets.count != inputs.count {
        throw CashuMintError.duplicateInputs
    }
    
    // 4. Get keyset info for fee calculation and unit validation
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
    
    // 5. Validate all inputs are same unit
    if inputUnits.count > 1 {
        throw CashuMintError.multipleUnits
    }
    
    let inputUnit = inputUnits.first!
    if inputUnit != quote.unit {
        throw CashuMintError.inputOutputUnitMismatch
    }
    
    // 6. Calculate input fees
    let inputFees = feeCalculator.calculateInputFees(proofs: inputs, keysets: inputKeysets)
    
    // 7. Validate inputs are sufficient: sum(inputs) >= amount + fee_reserve + input_fees
    let inputSum = inputs.reduce(0) { $0 + $1.amount }
    let requiredAmount = quote.amount + quote.feeReserve + inputFees
    
    if inputSum < requiredAmount {
        throw CashuMintError.transactionNotBalanced(inputSum, requiredAmount)
    }
    
    // 8. Validate all input proofs (signatures, not spent, not pending)
    let validationResult = try await proofValidator.validateProofs(inputs)
    
    if !validationResult.isAllValid {
        if let (_, error) = validationResult.invalid.first {
            switch error {
            case .proofAlreadySpent:
                throw CashuMintError.tokenAlreadySpent
            case .proofIsPending:
                throw CashuMintError.tokenAlreadySpent
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
    
    // 9. Mark quote as pending and proofs as pending
    try await quoteManager.markMeltQuoteAsPending(id: quoteId)
    
    let pendingExpiry = Date().addingTimeInterval(300) // 5 minute pending timeout
    try await spentProofStore.markAsPending(inputs, quoteId: quoteId, expiresAt: pendingExpiry)
    
    // Compute Y values for later
    let yValues = try await proofValidator.computeYs(from: inputs).map { $0.1 }
    
    // 10. Attempt Lightning payment (this can take a long time!)
    let paymentResult: PaymentResult
    do {
        paymentResult = try await lightningBackend.payInvoice(
            bolt11: quote.request,
            maxFeeSat: quote.feeReserve,
            timeoutSecs: 60
        )
    } catch let error as LightningError {
        // Payment failed - revert pending state
        try await quoteManager.markMeltQuoteAsFailed(id: quoteId)
        try await spentProofStore.removePending(ys: yValues)
        throw CashuMintError.lightningPaymentFailed(error.description)
    }
    
    // 11. Handle payment result
    switch paymentResult.status {
    case .succeeded:
        // Payment succeeded!
        let feePaid = paymentResult.feeSat ?? 0
        let preimage = paymentResult.preimage ?? ""
        
        // Move proofs from pending to spent
        try await spentProofStore.movePendingToSpent(ys: yValues)
        
        // Mark quote as paid
        try await quoteManager.markMeltQuoteAsPaid(id: quoteId, preimage: preimage, feePaid: feePaid)
        
        // Calculate overpaid fees for change (NUT-08)
        var changeSignatures: [BlindSignatureData]? = nil
        
        if !blankOutputs.isEmpty {
            let overpaid = feeCalculator.calculateOverpaidAmount(
                inputSum: inputSum,
                amount: quote.amount,
                actualFeePaid: feePaid,
                inputFees: inputFees
            )
            
            if overpaid > 0 {
                // Calculate change amounts (powers of 2)
                let changeAmounts = feeCalculator.calculateChangeAmounts(amount: overpaid)
                
                // Sign blank outputs with the change amounts
                changeSignatures = try await signChangeOutputs(
                    blankOutputs: blankOutputs,
                    changeAmounts: changeAmounts,
                    signingService: signingService,
                    keysetManager: keysetManager,
                    unit: quote.unit,
                    logger: logger
                )
            }
        }
        
        logger.info("Melt successful", metadata: [
            "quote_id": .string(quoteId),
            "amount": .stringConvertible(quote.amount),
            "fee_paid": .stringConvertible(feePaid),
            "input_fees": .stringConvertible(inputFees),
            "change_count": .stringConvertible(changeSignatures?.count ?? 0)
        ])
        
        return MeltQuoteResponse(from: quote, change: changeSignatures)
        
    case .pending:
        // Payment still pending - keep proofs pending
        throw CashuMintError.quotePending
        
    case .failed:
        // Payment failed - revert pending state
        try await quoteManager.markMeltQuoteAsFailed(id: quoteId)
        try await spentProofStore.removePending(ys: yValues)
        throw CashuMintError.lightningPaymentFailed(paymentResult.error ?? "Unknown error")
    }
}

// MARK: - Change Output Signing (NUT-08)

/// Sign blank outputs with change amounts
private func signChangeOutputs(
    blankOutputs: [BlindedMessageData],
    changeAmounts: [Int],
    signingService: SigningService,
    keysetManager: KeysetManager,
    unit: String,
    logger: Logger
) async throws -> [BlindSignatureData] {
    var signatures: [BlindSignatureData] = []
    
    // Get active keyset for the unit
    let activeKeyset = try await keysetManager.getActiveKeyset(unit: unit)
    
    // Sign outputs with change amounts
    // We use as many blank outputs as we need for the change amounts
    var outputIndex = 0
    
    for changeAmount in changeAmounts {
        guard outputIndex < blankOutputs.count else {
            logger.warning("Not enough blank outputs for change", metadata: [
                "needed": .stringConvertible(changeAmounts.count),
                "provided": .stringConvertible(blankOutputs.count)
            ])
            break
        }
        
        let blankOutput = blankOutputs[outputIndex]
        
        // Create a new blinded message with the actual change amount
        let changeMessage = BlindedMessageData(
            amount: changeAmount,
            id: activeKeyset.id,
            B_: blankOutput.B_,
            witness: nil
        )
        
        let signature = try await signingService.signBlindedMessage(changeMessage)
        signatures.append(signature)
        
        outputIndex += 1
    }
    
    return signatures
}

// MARK: - Response Types

extension MeltQuoteResponse: ResponseCodable {}
extension MeltResponse: ResponseCodable {}
