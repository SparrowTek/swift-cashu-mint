import Hummingbird
import Logging
import Foundation

/// Build the Hummingbird application with all routes and middleware
func buildApplication(
    config: MintConfiguration,
    host: String,
    port: Int,
    logger: Logger
) async throws -> some ApplicationProtocol {
    // Configure JSON encoder/decoder for snake_case (Cashu API uses snake_case)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    
    // Create router
    let router = Router()
    
    // Add routes
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
    
    // NUT-06: Mint Information
    router.get("/v1/info") { _, _ in
        GetInfoResponse(
            name: config.name,
            pubkey: nil, // Will be populated once keysets are loaded
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
                nut9: NUTSupportInfo(supported: true)
            )
        )
    }
    
    // NUT-01: Public Keys (placeholder)
    router.get("/v1/keys") { _, _ in
        GetKeysResponse(keysets: [])
    }
    
    // NUT-02: Keysets (placeholder)
    router.get("/v1/keysets") { _, _ in
        GetKeysetsResponse(keysets: [])
    }
    
    // Configure application
    let app = Application(
        router: router,
        configuration: .init(
            address: .hostname(host, port: port)
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
    
    enum CodingKeys: String, CodingKey {
        case nut4 = "4"
        case nut5 = "5"
        case nut7 = "7"
        case nut8 = "8"
        case nut9 = "9"
    }
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
