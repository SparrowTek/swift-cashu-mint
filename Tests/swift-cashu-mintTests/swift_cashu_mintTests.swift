import Testing
@testable import swift_cashu_mint

@Suite("Configuration Tests")
struct ConfigurationTests {
    
    @Test("Default configuration values")
    func defaultConfiguration() throws {
        let config = MintConfiguration(
            databaseURL: "postgres://localhost/test"
        )
        
        #expect(config.host == "0.0.0.0")
        #expect(config.port == 3338)
        #expect(config.name == "Swift Cashu Mint")
        #expect(config.unit == "sat")
        #expect(config.inputFeePPK == 0)
        #expect(config.maxOrder == 20)
        #expect(config.lightningBackend == .mock)
        #expect(config.mintMinAmount == 1)
        #expect(config.mintMaxAmount == 1_000_000)
        #expect(config.meltMinAmount == 1)
        #expect(config.meltMaxAmount == 1_000_000)
    }
    
    @Test("Custom configuration values")
    func customConfiguration() throws {
        let config = MintConfiguration(
            host: "127.0.0.1",
            port: 8080,
            name: "Test Mint",
            description: "A test mint",
            databaseURL: "postgres://localhost/cashu",
            lightningBackend: .mock,
            unit: "sat",
            inputFeePPK: 100,
            maxOrder: 15,
            mintMinAmount: 10,
            mintMaxAmount: 100_000,
            meltMinAmount: 10,
            meltMaxAmount: 100_000
        )
        
        #expect(config.host == "127.0.0.1")
        #expect(config.port == 8080)
        #expect(config.name == "Test Mint")
        #expect(config.description == "A test mint")
        #expect(config.inputFeePPK == 100)
        #expect(config.maxOrder == 15)
        #expect(config.mintMinAmount == 10)
        #expect(config.mintMaxAmount == 100_000)
    }
    
    @Test("LightningBackendType raw values")
    func lightningBackendRawValues() {
        #expect(LightningBackendType.lnd.rawValue == "lnd")
        #expect(LightningBackendType.mock.rawValue == "mock")
        
        #expect(LightningBackendType(rawValue: "lnd") == .lnd)
        #expect(LightningBackendType(rawValue: "mock") == .mock)
        #expect(LightningBackendType(rawValue: "invalid") == nil)
    }
}
