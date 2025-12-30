import ArgumentParser
import Hummingbird
import Logging
import FluentPostgresDriver
import Foundation

@main
struct SwiftCashuMint: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-cashu-mint",
        abstract: "A Cashu mint server implementation in Swift",
        version: "0.1.0",
        subcommands: [Serve.self, Migrate.self],
        defaultSubcommand: Serve.self
    )
}

// MARK: - Serve Command

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the mint server"
    )
    
    @Option(name: .shortAndLong, help: "Host address to bind")
    var host: String?
    
    @Option(name: .shortAndLong, help: "Port to listen on")
    var port: Int?
    
    @Flag(name: .long, help: "Enable verbose logging")
    var verbose = false
    
    func run() async throws {
        // Setup logging
        let logLevel: Logger.Level = verbose ? .debug : .info
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = logLevel
            return handler
        }
        
        let logger = Logger(label: "swift-cashu-mint")
        
        logger.info("Starting Swift Cashu Mint...")
        
        // Load configuration
        let config: MintConfiguration
        do {
            config = try MintConfiguration()
        } catch {
            logger.error("Configuration error: \(error)")
            throw error
        }
        
        // Override host/port from CLI if provided
        let bindHost = host ?? config.host
        let bindPort = port ?? config.port
        
        logger.info("Mint name: \(config.name)")
        logger.info("Lightning backend: \(config.lightningBackend.rawValue)")
        logger.info("Unit: \(config.unit)")
        
        // Build and run the application
        let app = try await buildApplication(
            config: config,
            host: bindHost,
            port: bindPort,
            logger: logger
        )
        
        try await app.run()
    }
}

// MARK: - Migrate Command

struct Migrate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run database migrations"
    )
    
    @Flag(name: .long, help: "Revert all migrations")
    var revert = false
    
    func run() async throws {
        var logger = Logger(label: "swift-cashu-mint.migrate")
        logger.logLevel = .info
        
        logger.info("Running database migrations...")
        
        _ = try MintConfiguration()
        
        // TODO: Setup Fluent and run migrations
        // This will be implemented in Phase 2 when we create the database models
        
        if revert {
            logger.info("Reverting migrations...")
            // fluent.revert()
        } else {
            logger.info("Applying migrations...")
            // fluent.migrate()
        }
        
        logger.info("Migrations complete")
    }
}
