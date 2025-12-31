import Foundation
import Hummingbird
import Logging

// MARK: - Mint Routes (NUT-04, NUT-23)

/// Add mint routes to the router
/// - POST /v1/mint/quote/bolt11 - Request a mint quote
/// - GET /v1/mint/quote/bolt11/{quote_id} - Check mint quote status
/// - POST /v1/mint/bolt11 - Mint tokens
func addMintRoutes<Context: RequestContext>(
    to router: Router<Context>,
    keysetManager: KeysetManager,
    signingService: SigningService,
    quoteManager: QuoteManager,
    lightningBackend: any LightningBackend,
    config: MintConfiguration,
    logger: Logger
) {
    // POST /v1/mint/quote/bolt11 - Request a mint quote (NUT-04, NUT-23)
    router.post("/v1/mint/quote/bolt11") { request, context in
        let quoteRequest = try await request.decode(as: MintQuoteRequest.self, context: context)
        
        return try await createMintQuote(
            request: quoteRequest,
            quoteManager: quoteManager,
            lightningBackend: lightningBackend,
            config: config,
            logger: logger
        )
    }
    
    // GET /v1/mint/quote/bolt11/{quote_id} - Check mint quote status (NUT-04)
    router.get("/v1/mint/quote/bolt11/{quote_id}") { request, context in
        let quoteId = context.parameters.get("quote_id") ?? ""

        // Validate quote ID format
        do {
            try InputValidator.validateQuoteId(quoteId)
        } catch {
            throw CashuMintError.quoteNotFound(quoteId)
        }
        
        return try await checkMintQuote(
            quoteId: quoteId,
            quoteManager: quoteManager,
            lightningBackend: lightningBackend,
            logger: logger
        )
    }
    
    // POST /v1/mint/bolt11 - Mint tokens (NUT-04, NUT-23)
    router.post("/v1/mint/bolt11") { request, context in
        let mintRequest = try await request.decode(as: MintRequest.self, context: context)
        
        return try await mintTokens(
            request: mintRequest,
            keysetManager: keysetManager,
            signingService: signingService,
            quoteManager: quoteManager,
            lightningBackend: lightningBackend,
            logger: logger
        )
    }
}

// MARK: - POST /v1/mint/quote/bolt11 (NUT-04, NUT-23)

/// Create a mint quote with Lightning invoice
private func createMintQuote(
    request: MintQuoteRequest,
    quoteManager: QuoteManager,
    lightningBackend: any LightningBackend,
    config: MintConfiguration,
    logger: Logger
) async throws -> MintQuoteResponse {
    // 1. Validate unit
    if request.unit != config.unit {
        throw CashuMintError.unitNotSupported(request.unit)
    }
    
    // 2. Validate amount within limits
    if request.amount < config.mintMinAmount || request.amount > config.mintMaxAmount {
        throw CashuMintError.amountOutsideLimit(request.amount, config.mintMinAmount, config.mintMaxAmount)
    }
    
    // 3. Create Lightning invoice
    let invoice = try await lightningBackend.createInvoice(
        amountSat: request.amount,
        memo: request.description,
        expirySecs: 3600  // 1 hour expiry
    )
    
    // 4. Create quote in database
    let quote = try await quoteManager.createMintQuote(
        amount: request.amount,
        unit: request.unit,
        request: invoice.bolt11,
        paymentHash: invoice.paymentHash,
        expiry: invoice.expiry,
        description: request.description
    )
    
    logger.info("Mint quote created", metadata: [
        "quote_id": .string(quote.quoteId),
        "amount": .stringConvertible(request.amount),
        "unit": .string(request.unit)
    ])
    
    return MintQuoteResponse(from: quote)
}

// MARK: - GET /v1/mint/quote/bolt11/{quote_id} (NUT-04)

/// Check mint quote status and update if invoice was paid
private func checkMintQuote(
    quoteId: String,
    quoteManager: QuoteManager,
    lightningBackend: any LightningBackend,
    logger: Logger
) async throws -> MintQuoteResponse {
    // 1. Get quote from database
    let quote: MintQuote
    do {
        quote = try await quoteManager.getMintQuote(id: quoteId)
    } catch is QuoteError {
        throw CashuMintError.quoteNotFound(quoteId)
    }
    
    // 2. If quote is unpaid, check Lightning invoice status
    if quote.state == .unpaid {
        let invoiceStatus = try await lightningBackend.getInvoiceStatus(paymentHash: quote.paymentHash)
        
        switch invoiceStatus {
        case .paid:
            try await quoteManager.markMintQuoteAsPaid(id: quoteId)
            // Refresh quote to get updated state
            let updatedQuote = try await quoteManager.getMintQuote(id: quoteId)
            return MintQuoteResponse(from: updatedQuote)
            
        case .expired:
            throw CashuMintError.quoteExpired
            
        case .pending, .cancelled:
            // Still unpaid or cancelled
            break
        }
    }
    
    // 3. Check if expired
    if quote.expiry < Date() && quote.state == .unpaid {
        throw CashuMintError.quoteExpired
    }
    
    return MintQuoteResponse(from: quote)
}

// MARK: - POST /v1/mint/bolt11 (NUT-04, NUT-23)

/// Mint tokens after quote is paid
private func mintTokens(
    request: MintRequest,
    keysetManager: KeysetManager,
    signingService: SigningService,
    quoteManager: QuoteManager,
    lightningBackend: any LightningBackend,
    logger: Logger
) async throws -> MintResponse {
    let quoteId = request.quote
    let outputs = request.outputs
    
    // 1. Validate quote exists and is PAID
    let quote: MintQuote
    do {
        // First get the quote
        let fetchedQuote = try await quoteManager.getMintQuote(id: quoteId)
        
        // If unpaid, check Lightning status first
        if fetchedQuote.state == .unpaid {
            let invoiceStatus = try await lightningBackend.getInvoiceStatus(paymentHash: fetchedQuote.paymentHash)
            if case .paid = invoiceStatus {
                try await quoteManager.markMintQuoteAsPaid(id: quoteId)
            }
        }
        
        // Now validate for minting
        quote = try await quoteManager.validateMintQuoteForMinting(id: quoteId)
    } catch let error as QuoteError {
        switch error {
        case .quoteNotFound:
            throw CashuMintError.quoteNotFound(quoteId)
        case .quoteExpired:
            throw CashuMintError.quoteExpired
        case .quoteNotPaid:
            throw CashuMintError.quoteNotPaid
        case .quoteAlreadyIssued:
            throw CashuMintError.tokensAlreadyIssued
        default:
            throw CashuMintError.internalError(error.description)
        }
    }
    
    // 2. Validate outputs are not empty
    guard !outputs.isEmpty else {
        throw CashuMintError.transactionNotBalanced(quote.amount, 0)
    }

    // 2.5. Validate output formats
    do {
        try InputValidator.validateBlindedMessagesFormat(outputs)
    } catch let error as ValidationError {
        throw CashuMintError.from(error)
    }

    // 3. Check for duplicate outputs
    let outputBlinds = Set(outputs.map { $0.B_ })
    if outputBlinds.count != outputs.count {
        throw CashuMintError.duplicateOutputs
    }
    
    // 4. Validate output amounts sum equals quote amount
    let outputSum = outputs.reduce(0) { $0 + $1.amount }
    if outputSum != quote.amount {
        throw CashuMintError.amountMismatch(quote.amount, outputSum)
    }
    
    // 5. Validate all outputs use active keysets with correct unit
    for output in outputs {
        do {
            let keyset = try await keysetManager.getKeyset(id: output.id)
            
            if !keyset.active {
                throw CashuMintError.keysetInactive(output.id)
            }
            
            if keyset.unit != quote.unit {
                throw CashuMintError.inputOutputUnitMismatch
            }
        } catch is KeysetManagerError {
            throw CashuMintError.keysetUnknown(output.id)
        }
    }
    
    // 6. Sign all blinded messages
    let signatures: [BlindSignatureData]
    do {
        signatures = try await signingService.signBlindedMessages(outputs)
    } catch let error as SigningError {
        logger.error("Signing failed during mint: \(error.description)")
        throw CashuMintError.internalError("Signing failed")
    }
    
    // 7. Mark quote as issued
    try await quoteManager.markMintQuoteAsIssued(id: quoteId)
    
    logger.info("Tokens minted", metadata: [
        "quote_id": .string(quoteId),
        "output_count": .stringConvertible(outputs.count),
        "total_amount": .stringConvertible(outputSum)
    ])
    
    return MintResponse(signatures: signatures)
}

// MARK: - Response Types

extension MintQuoteResponse: ResponseCodable {}
extension MintResponse: ResponseCodable {}
