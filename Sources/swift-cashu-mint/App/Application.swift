import Hummingbird
import Logging
import Fluent
import FluentPostgresDriver
import Foundation

/// Build the Hummingbird application with all routes and middleware
/// This is the main entry point that wires together all services and routes
func buildApplication(
    config: MintConfiguration,
    database: Database,
    lightningBackend: any LightningBackend,
    logger: Logger
) async throws -> some ApplicationProtocol {
    
    // MARK: - Initialize Services
    
    let keysetManager = KeysetManager(database: database)
    let signingService = SigningService(database: database, keysetManager: keysetManager)
    let proofValidator = ProofValidator(database: database, keysetManager: keysetManager)
    let spentProofStore = SpentProofStore(database: database)
    let quoteManager = QuoteManager(database: database, config: config)
    let feeCalculator = FeeCalculator()
    let spendingConditionValidator = SpendingConditionValidator(logger: logger)
    
    // Load all keysets from database into memory
    try await keysetManager.loadAllKeysets()
    
    // Ensure we have at least one active keyset
    do {
        _ = try await keysetManager.getActiveKeyset(unit: config.unit)
    } catch {
        // No active keyset exists, create one
        logger.info("Creating initial keyset for unit: \(config.unit)")
        _ = try await keysetManager.generateKeyset(
            unit: config.unit,
            inputFeePpk: config.inputFeePPK,
            maxOrder: config.maxOrder
        )
    }
    
    // Get the active keyset pubkey for /v1/info
    let activeKeyset = try await keysetManager.getActiveKeyset(unit: config.unit)
    let mintPubkey = activeKeyset.publicKeys[1]  // Use the 1 sat key as mint pubkey
    
    // MARK: - Create Router

    let router = Router()

    // Add error middleware (first, to catch all errors including rate limit)
    router.middlewares.add(CashuErrorMiddleware(logger: logger))

    // Add rate limiting middleware
    let rateLimitStore = RateLimitStore()
    router.middlewares.add(RateLimitMiddleware(
        store: rateLimitStore,
        config: config.rateLimitConfig,
        logger: logger
    ))

    // Add request size limit middleware
    router.middlewares.add(RequestSizeLimitMiddleware())

    // Add request logging middleware for structured logs
    router.middlewares.add(RequestLoggingMiddleware(logger: logger))
    
    // MARK: - Basic Routes
    
    // Root endpoint
    router.get("/") { _, _ in
        "Swift Cashu Mint v0.1.0"
    }
    
    // Health check endpoint
    router.get("/health") { _, _ in
        HealthResponse(
            status: "ok",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }
    
    // MARK: - NUT-06: Mint Information
    
    let infoResponse = GetInfoResponse(
        name: config.name,
        pubkey: mintPubkey,
        version: "SwiftMint/0.1.0",
        description: config.description,
        descriptionLong: config.descriptionLong,
        contact: config.contact.isEmpty ? nil : config.contact,
        motd: config.motd,
        iconUrl: config.iconURL,
        tosUrl: config.tosURL,
        nuts: NutsInfo(
            nut4: NUT4Info(
                methods: [
                    PaymentMethodInfo(method: "bolt11", unit: config.unit, minAmount: config.mintMinAmount, maxAmount: config.mintMaxAmount)
                ],
                disabled: false
            ),
            nut5: NUT5Info(
                methods: [
                    PaymentMethodInfo(method: "bolt11", unit: config.unit, minAmount: config.meltMinAmount, maxAmount: config.meltMaxAmount)
                ],
                disabled: false
            ),
            nut7: NUTSupportInfo(supported: true),
            nut8: NUTSupportInfo(supported: true),
            nut9: NUTSupportInfo(supported: true),
            nut10: NUTSupportInfo(supported: true),
            nut11: NUTSupportInfo(supported: true),
            nut12: NUTSupportInfo(supported: true),
            nut14: NUTSupportInfo(supported: true),
            nut15: NUT15Info(
                methods: [
                    NUT15MethodInfo(method: "bolt11", unit: config.unit, mpp: true)
                ],
                disabled: false
            )
        )
    )
    
    router.get("/v1/info") { _, _ in
        infoResponse
    }
    
    // MARK: - Add Routes
    
    // NUT-01/NUT-02: Keys routes
    addKeyRoutes(to: router, keysetManager: keysetManager, logger: logger)
    
    // NUT-03: Swap route
    addSwapRoutes(
        to: router,
        keysetManager: keysetManager,
        signingService: signingService,
        proofValidator: proofValidator,
        spentProofStore: spentProofStore,
        feeCalculator: feeCalculator,
        spendingConditionValidator: spendingConditionValidator,
        logger: logger
    )
    
    // NUT-04/NUT-23: Mint routes
    addMintRoutes(
        to: router,
        keysetManager: keysetManager,
        signingService: signingService,
        quoteManager: quoteManager,
        lightningBackend: lightningBackend,
        config: config,
        logger: logger
    )
    
    // NUT-05/NUT-08/NUT-23: Melt routes
    addMeltRoutes(
        to: router,
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
    
    // NUT-07: Check state route
    addCheckRoutes(
        to: router,
        proofValidator: proofValidator,
        spentProofStore: spentProofStore,
        logger: logger
    )
    
    // NUT-09: Restore route
    addRestoreRoutes(
        to: router,
        signingService: signingService,
        logger: logger
    )
    
    // MARK: - Configure Application
    
    let app = Application(
        router: router,
        configuration: .init(
            address: .hostname(config.host, port: config.port)
        ),
        logger: logger
    )
    
    return app
}

// MARK: - Response Models

struct HealthResponse: ResponseCodable {
    let status: String
    let timestamp: String
}

// MARK: - NUT-06 Info Response

struct GetInfoResponse: ResponseCodable {
    let name: String
    let pubkey: String?
    let version: String
    let description: String?
    let descriptionLong: String?
    let contact: [[String: String]]?
    let motd: String?
    let iconUrl: String?
    let tosUrl: String?
    let nuts: NutsInfo
    
    enum CodingKeys: String, CodingKey {
        case name, pubkey, version, description
        case descriptionLong = "description_long"
        case contact, motd
        case iconUrl = "icon_url"
        case tosUrl = "tos_url"
        case nuts
    }
}

struct NutsInfo: Codable, Sendable {
    let nut4: NUT4Info
    let nut5: NUT5Info
    let nut7: NUTSupportInfo
    let nut8: NUTSupportInfo
    let nut9: NUTSupportInfo
    let nut10: NUTSupportInfo
    let nut11: NUTSupportInfo
    let nut12: NUTSupportInfo
    let nut14: NUTSupportInfo
    let nut15: NUT15Info

    enum CodingKeys: String, CodingKey {
        case nut4 = "4"
        case nut5 = "5"
        case nut7 = "7"
        case nut8 = "8"
        case nut9 = "9"
        case nut10 = "10"
        case nut11 = "11"
        case nut12 = "12"
        case nut14 = "14"
        case nut15 = "15"
    }
}

/// NUT-15 Multi-path Payments info
struct NUT15Info: Codable, Sendable {
    let methods: [NUT15MethodInfo]
    let disabled: Bool
}

struct NUT15MethodInfo: Codable, Sendable {
    let method: String
    let unit: String
    let mpp: Bool
}

struct NUT4Info: Codable, Sendable {
    let methods: [PaymentMethodInfo]
    let disabled: Bool
}

struct NUT5Info: Codable, Sendable {
    let methods: [PaymentMethodInfo]
    let disabled: Bool
}

struct PaymentMethodInfo: Codable, Sendable {
    let method: String
    let unit: String
    let minAmount: Int?
    let maxAmount: Int?
    
    enum CodingKeys: String, CodingKey {
        case method, unit
        case minAmount = "min_amount"
        case maxAmount = "max_amount"
    }
}

struct NUTSupportInfo: Codable, Sendable {
    let supported: Bool
}

// MARK: - NUT-01/02 Keys Response

struct GetKeysResponse: ResponseCodable {
    let keysets: [KeysetResponse]
}

struct KeysetResponse: Codable, Sendable {
    let id: String
    let unit: String
    let keys: [String: String]
}

struct GetKeysetsResponse: ResponseCodable {
    let keysets: [KeysetInfo]
}

struct KeysetInfo: Codable, Sendable {
    let id: String
    let unit: String
    let active: Bool
    let inputFeePpk: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, unit, active
        case inputFeePpk = "input_fee_ppk"
    }
}
