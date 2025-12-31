import ArgumentParser
import Hummingbird
import Logging
import Fluent
import FluentPostgresDriver
import Foundation
import NIOCore

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
    
    @Flag(name: .long, help: "Output logs in JSON format")
    var jsonLogs = false

    func run() async throws {
        // Setup logging with optional JSON format
        configureLogging(verbose: verbose, jsonFormat: jsonLogs)

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
        
        // Create a mutable copy with overridden host/port if needed
        let finalHost = host ?? config.host
        let finalPort = port ?? config.port
        
        logger.info("Mint name: \(config.name)")
        logger.info("Lightning backend: \(config.lightningBackend.rawValue)")
        logger.info("Unit: \(config.unit)")
        logger.info("Binding to: \(finalHost):\(finalPort)")
        
        // Setup event loop and thread pool
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton
        let threadPool = NIOThreadPool(numberOfThreads: 4)
        threadPool.start()

        // Setup database with connection pooling
        let dbFactory = DatabaseFactory(
            logger: logger,
            poolConfig: .fromEnvironment()
        )

        let databases: Databases
        let database: any Database
        do {
            (databases, database) = try dbFactory.createDatabase(
                url: config.databaseURL,
                threadPool: threadPool,
                eventLoopGroup: eventLoopGroup
            )
        } catch let error as DatabaseConfigurationError {
            logger.error("Database configuration failed: \(error.description)")
            throw error
        }

        // Test database connection with retry logic
        do {
            try await dbFactory.testConnection(database: database)
        } catch {
            logger.error("Database connection test failed: \(error)")
            throw error
        }

        // Add migrations
        let migrations = Migrations()
        migrations.add(CreateMintTables())

        // Run migrations
        logger.info("Running database migrations...")
        let migrator = Migrator(
            databases: databases,
            migrations: migrations,
            logger: logger,
            on: eventLoopGroup.next()
        )
        _ = migrator.setupIfNeeded()
        _ = migrator.prepareBatch()
        logger.info("Database migrations complete")
        
        // Create Lightning backend
        let lightningBackend = try LightningBackendFactory.create(from: config)
        
        logger.info("Lightning backend initialized: \(config.lightningBackend.rawValue)")
        
        // Create updated config with final host/port
        let finalConfig = MintConfiguration(
            host: finalHost,
            port: finalPort,
            name: config.name,
            description: config.description,
            descriptionLong: config.descriptionLong,
            motd: config.motd,
            iconURL: config.iconURL,
            tosURL: config.tosURL,
            contact: config.contact,
            databaseURL: config.databaseURL,
            lightningBackend: config.lightningBackend,
            lndHost: config.lndHost,
            lndMacaroonPath: config.lndMacaroonPath,
            lndCertPath: config.lndCertPath,
            unit: config.unit,
            inputFeePPK: config.inputFeePPK,
            maxOrder: config.maxOrder,
            mintMinAmount: config.mintMinAmount,
            mintMaxAmount: config.mintMaxAmount,
            meltMinAmount: config.meltMinAmount,
            meltMaxAmount: config.meltMaxAmount
        )
        
        // Build and run the application
        let app = try await buildApplication(
            config: finalConfig,
            database: database,
            lightningBackend: lightningBackend,
            logger: logger
        )
        
        try await app.run()
        
        // Cleanup - shutdown must be done synchronously on the event loop
        let promise = eventLoopGroup.next().makePromise(of: Void.self)
        eventLoopGroup.next().execute {
            databases.shutdown()
            promise.succeed(())
        }
        try await promise.futureResult.get()
        try await threadPool.shutdownGracefully()
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
        
        let config = try MintConfiguration()
        
        // Setup event loop and thread pool
        let eventLoopGroup = MultiThreadedEventLoopGroup.singleton
        let threadPool = NIOThreadPool(numberOfThreads: 4)
        threadPool.start()
        
        // Setup database
        let databases = Databases(threadPool: threadPool, on: eventLoopGroup)
        
        // Parse DATABASE_URL and configure PostgreSQL
        let databaseURL = config.databaseURL
        guard let url = URL(string: databaseURL) else {
            logger.error("Invalid DATABASE_URL")
            throw ConfigurationError.invalidValue("DATABASE_URL", "Invalid URL format")
        }
        
        var tlsConfig: PostgresConnection.Configuration.TLS = .disable
        if url.scheme == "postgresql" && url.host?.contains("localhost") != true {
            tlsConfig = .prefer(try .init(configuration: .clientDefault))
        }
        
        let postgresConfig = PostgresConnection.Configuration(
            host: url.host ?? "localhost",
            port: url.port ?? 5432,
            username: url.user ?? "postgres",
            password: url.password,
            database: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            tls: tlsConfig
        )
        
        let sqlConfig = SQLPostgresConfiguration(coreConfiguration: postgresConfig)
        databases.use(DatabaseConfigurationFactory.postgres(configuration: sqlConfig), as: .psql)
        
        // Add migrations
        let migrations = Migrations()
        migrations.add(CreateMintTables())
        
        let migrator = Migrator(
            databases: databases,
            migrations: migrations,
            logger: logger,
            on: eventLoopGroup.next()
        )
        
        if revert {
            logger.info("Reverting migrations...")
            _ = migrator.revertAllBatches()
        } else {
            logger.info("Applying migrations...")
            _ = migrator.setupIfNeeded()
            _ = migrator.prepareBatch()
        }
        
        logger.info("Migrations complete")
        
        // Cleanup - shutdown must be done synchronously on the event loop
        let promise = eventLoopGroup.next().makePromise(of: Void.self)
        eventLoopGroup.next().execute {
            databases.shutdown()
            promise.succeed(())
        }
        try await promise.futureResult.get()
        try await threadPool.shutdownGracefully()
    }
}
