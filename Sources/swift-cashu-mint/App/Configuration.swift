import Foundation

/// Lightning backend type for the mint
enum LightningBackendType: String, Sendable {
    case lnd
    case mock
}

/// Mint server configuration loaded from environment variables
/// Follows 12-factor app principles
struct MintConfiguration: Sendable {
    // MARK: - Server Settings
    
    /// Host address to bind (MINT_HOST, default "0.0.0.0")
    let host: String
    
    /// Port to listen on (MINT_PORT, default 3338)
    let port: Int
    
    // MARK: - Mint Identity (NUT-06)
    
    /// Mint name (MINT_NAME)
    let name: String
    
    /// Short description (MINT_DESCRIPTION)
    let description: String?
    
    /// Long description (MINT_DESCRIPTION_LONG)
    let descriptionLong: String?
    
    /// Message of the day (MINT_MOTD)
    let motd: String?
    
    /// Icon URL (MINT_ICON_URL)
    let iconURL: String?
    
    /// Terms of Service URL (MINT_TOS_URL)
    let tosURL: String?
    
    /// Contact information (MINT_CONTACT, JSON array of {method, info})
    let contact: [[String: String]]
    
    // MARK: - Database
    
    /// PostgreSQL connection URL (DATABASE_URL)
    let databaseURL: String
    
    // MARK: - Lightning
    
    /// Lightning backend type (LIGHTNING_BACKEND: lnd|mock)
    let lightningBackend: LightningBackendType
    
    /// LND host and port (LND_HOST)
    let lndHost: String?
    
    /// Path to LND macaroon file (LND_MACAROON_PATH)
    let lndMacaroonPath: String?
    
    /// Path to LND TLS certificate (LND_CERT_PATH)
    let lndCertPath: String?
    
    // MARK: - Keyset Settings
    
    /// Unit for the keyset (MINT_UNIT, default "sat")
    let unit: String
    
    /// Input fee in parts per thousand (MINT_INPUT_FEE_PPK, default 0)
    let inputFeePPK: Int
    
    /// Maximum order for keyset amounts (MINT_MAX_ORDER, default 20 = 2^20 sats)
    let maxOrder: Int
    
    // MARK: - Limits
    
    /// Minimum amount for minting (MINT_MIN_AMOUNT, default 1)
    let mintMinAmount: Int
    
    /// Maximum amount for minting (MINT_MAX_AMOUNT, default 1_000_000)
    let mintMaxAmount: Int
    
    /// Minimum amount for melting (MELT_MIN_AMOUNT, default 1)
    let meltMinAmount: Int
    
    /// Maximum amount for melting (MELT_MAX_AMOUNT, default 1_000_000)
    let meltMaxAmount: Int
    
    // MARK: - Initialization
    
    /// Initialize configuration from environment variables
    init() throws {
        // Server
        self.host = ProcessInfo.processInfo.environment["MINT_HOST"] ?? "0.0.0.0"
        self.port = Int(ProcessInfo.processInfo.environment["MINT_PORT"] ?? "3338") ?? 3338
        
        // Mint Identity
        self.name = ProcessInfo.processInfo.environment["MINT_NAME"] ?? "Swift Cashu Mint"
        self.description = ProcessInfo.processInfo.environment["MINT_DESCRIPTION"]
        self.descriptionLong = ProcessInfo.processInfo.environment["MINT_DESCRIPTION_LONG"]
        self.motd = ProcessInfo.processInfo.environment["MINT_MOTD"]
        self.iconURL = ProcessInfo.processInfo.environment["MINT_ICON_URL"]
        self.tosURL = ProcessInfo.processInfo.environment["MINT_TOS_URL"]
        
        // Parse contact JSON if provided
        if let contactJSON = ProcessInfo.processInfo.environment["MINT_CONTACT"],
           let data = contactJSON.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([[String: String]].self, from: data) {
            self.contact = parsed
        } else {
            self.contact = []
        }
        
        // Database - required
        guard let dbURL = ProcessInfo.processInfo.environment["DATABASE_URL"] else {
            throw ConfigurationError.missingRequired("DATABASE_URL")
        }
        self.databaseURL = dbURL
        
        // Lightning
        let backendString = ProcessInfo.processInfo.environment["LIGHTNING_BACKEND"] ?? "mock"
        guard let backend = LightningBackendType(rawValue: backendString) else {
            throw ConfigurationError.invalidValue("LIGHTNING_BACKEND", backendString)
        }
        self.lightningBackend = backend
        
        self.lndHost = ProcessInfo.processInfo.environment["LND_HOST"]
        self.lndMacaroonPath = ProcessInfo.processInfo.environment["LND_MACAROON_PATH"]
        self.lndCertPath = ProcessInfo.processInfo.environment["LND_CERT_PATH"]
        
        // Validate LND config if using LND backend
        if backend == .lnd {
            guard lndHost != nil else {
                throw ConfigurationError.missingRequired("LND_HOST (required when LIGHTNING_BACKEND=lnd)")
            }
            guard lndMacaroonPath != nil else {
                throw ConfigurationError.missingRequired("LND_MACAROON_PATH (required when LIGHTNING_BACKEND=lnd)")
            }
        }
        
        // Keyset
        self.unit = ProcessInfo.processInfo.environment["MINT_UNIT"] ?? "sat"
        self.inputFeePPK = Int(ProcessInfo.processInfo.environment["MINT_INPUT_FEE_PPK"] ?? "0") ?? 0
        self.maxOrder = Int(ProcessInfo.processInfo.environment["MINT_MAX_ORDER"] ?? "20") ?? 20
        
        // Limits
        self.mintMinAmount = Int(ProcessInfo.processInfo.environment["MINT_MIN_AMOUNT"] ?? "1") ?? 1
        self.mintMaxAmount = Int(ProcessInfo.processInfo.environment["MINT_MAX_AMOUNT"] ?? "1000000") ?? 1_000_000
        self.meltMinAmount = Int(ProcessInfo.processInfo.environment["MELT_MIN_AMOUNT"] ?? "1") ?? 1
        self.meltMaxAmount = Int(ProcessInfo.processInfo.environment["MELT_MAX_AMOUNT"] ?? "1000000") ?? 1_000_000
    }
    
    /// Initialize with explicit values (for testing)
    init(
        host: String = "0.0.0.0",
        port: Int = 3338,
        name: String = "Swift Cashu Mint",
        description: String? = nil,
        descriptionLong: String? = nil,
        motd: String? = nil,
        iconURL: String? = nil,
        tosURL: String? = nil,
        contact: [[String: String]] = [],
        databaseURL: String,
        lightningBackend: LightningBackendType = .mock,
        lndHost: String? = nil,
        lndMacaroonPath: String? = nil,
        lndCertPath: String? = nil,
        unit: String = "sat",
        inputFeePPK: Int = 0,
        maxOrder: Int = 20,
        mintMinAmount: Int = 1,
        mintMaxAmount: Int = 1_000_000,
        meltMinAmount: Int = 1,
        meltMaxAmount: Int = 1_000_000
    ) {
        self.host = host
        self.port = port
        self.name = name
        self.description = description
        self.descriptionLong = descriptionLong
        self.motd = motd
        self.iconURL = iconURL
        self.tosURL = tosURL
        self.contact = contact
        self.databaseURL = databaseURL
        self.lightningBackend = lightningBackend
        self.lndHost = lndHost
        self.lndMacaroonPath = lndMacaroonPath
        self.lndCertPath = lndCertPath
        self.unit = unit
        self.inputFeePPK = inputFeePPK
        self.maxOrder = maxOrder
        self.mintMinAmount = mintMinAmount
        self.mintMaxAmount = mintMaxAmount
        self.meltMinAmount = meltMinAmount
        self.meltMaxAmount = meltMaxAmount
    }
}

/// Configuration errors
enum ConfigurationError: Error, CustomStringConvertible {
    case missingRequired(String)
    case invalidValue(String, String)
    
    var description: String {
        switch self {
        case .missingRequired(let key):
            return "Missing required environment variable: \(key)"
        case .invalidValue(let key, let value):
            return "Invalid value '\(value)' for environment variable: \(key)"
        }
    }
}
