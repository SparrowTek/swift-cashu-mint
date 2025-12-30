import Foundation

/// Factory for creating Lightning backend instances based on configuration
enum LightningBackendFactory {
    
    /// Create a Lightning backend based on the mint configuration
    /// - Parameter config: The mint configuration
    /// - Returns: A Lightning backend instance
    static func create(from config: MintConfiguration) throws -> any LightningBackend {
        switch config.lightningBackend {
        case .mock:
            return MockLightningBackend()
            
        case .lnd:
            guard let host = config.lndHost else {
                throw LightningError.connectionFailed("LND_HOST not configured")
            }
            
            guard let macaroonPath = config.lndMacaroonPath else {
                throw LightningError.connectionFailed("LND_MACAROON_PATH not configured")
            }
            
            return try LNDBackend(
                host: host,
                macaroonPath: macaroonPath,
                certPath: config.lndCertPath
            )
        }
    }
    
    /// Create a mock backend for testing
    /// - Parameter initialBalance: Initial balance in satoshis
    /// - Returns: A mock Lightning backend
    static func createMock(initialBalance: Int = 1_000_000) -> MockLightningBackend {
        return MockLightningBackend(initialBalance: initialBalance)
    }
    
    /// Create an LND backend with explicit configuration
    /// - Parameters:
    ///   - host: LND REST API host
    ///   - macaroonPath: Path to the macaroon file
    ///   - certPath: Optional path to TLS certificate
    /// - Returns: An LND Lightning backend
    static func createLND(host: String, macaroonPath: String, certPath: String? = nil) throws -> LNDBackend {
        return try LNDBackend(host: host, macaroonPath: macaroonPath, certPath: certPath)
    }
    
    /// Create an LND backend with hex-encoded macaroon
    /// - Parameters:
    ///   - host: LND REST API host
    ///   - macaroonHex: Hex-encoded macaroon
    /// - Returns: An LND Lightning backend
    static func createLND(host: String, macaroonHex: String) throws -> LNDBackend {
        return try LNDBackend(host: host, macaroonHex: macaroonHex)
    }
}
