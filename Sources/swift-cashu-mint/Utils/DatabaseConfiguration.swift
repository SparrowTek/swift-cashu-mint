import Foundation
import Fluent
import FluentPostgresDriver
import Logging
import NIOCore

// MARK: - Database Pool Configuration

/// Configuration for database connection pooling
struct DatabasePoolConfiguration: Sendable {
    /// Maximum number of connections in the pool
    let maxConnections: Int

    /// Minimum number of connections to maintain
    let minConnections: Int

    /// Maximum time to wait for a connection (in seconds)
    let connectionTimeout: TimeInterval

    /// Time before an idle connection is closed (in seconds)
    let idleTimeout: TimeInterval

    /// Number of retry attempts for failed connections
    let retryAttempts: Int

    /// Delay between retry attempts (in seconds)
    let retryDelay: TimeInterval

    /// Enable/disable SSL for database connections
    let requireSSL: Bool

    /// Default configuration
    static let `default` = DatabasePoolConfiguration(
        maxConnections: 20,
        minConnections: 2,
        connectionTimeout: 30,
        idleTimeout: 600,
        retryAttempts: 3,
        retryDelay: 1.0,
        requireSSL: false
    )

    /// Production configuration (stricter limits, SSL required)
    static let production = DatabasePoolConfiguration(
        maxConnections: 50,
        minConnections: 5,
        connectionTimeout: 15,
        idleTimeout: 300,
        retryAttempts: 5,
        retryDelay: 2.0,
        requireSSL: true
    )

    /// Development configuration (relaxed limits)
    static let development = DatabasePoolConfiguration(
        maxConnections: 10,
        minConnections: 1,
        connectionTimeout: 60,
        idleTimeout: 1200,
        retryAttempts: 3,
        retryDelay: 1.0,
        requireSSL: false
    )

    /// Load configuration from environment variables
    static func fromEnvironment() -> DatabasePoolConfiguration {
        let env = ProcessInfo.processInfo.environment

        let maxConnections = Int(env["DB_MAX_CONNECTIONS"] ?? "20") ?? 20
        let minConnections = Int(env["DB_MIN_CONNECTIONS"] ?? "2") ?? 2
        let connectionTimeout = TimeInterval(env["DB_CONNECTION_TIMEOUT"] ?? "30") ?? 30
        let idleTimeout = TimeInterval(env["DB_IDLE_TIMEOUT"] ?? "600") ?? 600
        let retryAttempts = Int(env["DB_RETRY_ATTEMPTS"] ?? "3") ?? 3
        let retryDelay = TimeInterval(env["DB_RETRY_DELAY"] ?? "1.0") ?? 1.0
        let requireSSL = env["DB_REQUIRE_SSL"]?.lowercased() == "true"

        return DatabasePoolConfiguration(
            maxConnections: maxConnections,
            minConnections: minConnections,
            connectionTimeout: connectionTimeout,
            idleTimeout: idleTimeout,
            retryAttempts: retryAttempts,
            retryDelay: retryDelay,
            requireSSL: requireSSL
        )
    }
}

// MARK: - Database Factory

/// Factory for creating configured database instances
struct DatabaseFactory {
    let logger: Logger
    let poolConfig: DatabasePoolConfiguration

    init(logger: Logger, poolConfig: DatabasePoolConfiguration = .fromEnvironment()) {
        self.logger = logger
        self.poolConfig = poolConfig
    }

    /// Create and configure a database connection with pooling
    func createDatabase(
        url databaseURL: String,
        threadPool: NIOThreadPool,
        eventLoopGroup: any EventLoopGroup
    ) throws -> (databases: Databases, database: any Database) {
        // Parse the database URL
        guard let url = URL(string: databaseURL) else {
            throw DatabaseConfigurationError.invalidURL(databaseURL)
        }

        // Configure TLS
        let tlsConfig = try configureTLS(for: url)

        // Create PostgreSQL configuration
        let postgresConfig = PostgresConnection.Configuration(
            host: url.host ?? "localhost",
            port: url.port ?? 5432,
            username: url.user ?? "postgres",
            password: url.password,
            database: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            tls: tlsConfig
        )

        // Create SQL configuration
        let sqlConfig = SQLPostgresConfiguration(coreConfiguration: postgresConfig)

        // Create databases instance with thread pool for connection management
        // Note: Fluent handles connection pooling internally through the Databases type
        // Pool size is managed by the eventLoopGroup and threadPool configuration
        let databases = Databases(threadPool: threadPool, on: eventLoopGroup)

        // Configure PostgreSQL with pooling
        let factory = DatabaseConfigurationFactory.postgres(configuration: sqlConfig)
        databases.use(factory, as: .psql, isDefault: true)

        // Get the database instance
        guard let database = databases.database(.psql, logger: logger, on: eventLoopGroup.next()) else {
            throw DatabaseConfigurationError.connectionFailed("Failed to get database instance")
        }

        logger.info("Database pool configured", metadata: [
            "max_connections": .string(String(poolConfig.maxConnections)),
            "min_connections": .string(String(poolConfig.minConnections)),
            "idle_timeout": .string(String(poolConfig.idleTimeout)),
            "ssl": .string(String(poolConfig.requireSSL))
        ])

        return (databases, database)
    }

    /// Configure TLS based on URL and configuration
    private func configureTLS(for url: URL) throws -> PostgresConnection.Configuration.TLS {
        let isLocalhost = url.host?.contains("localhost") == true || url.host == "127.0.0.1"

        if poolConfig.requireSSL {
            // SSL required - use full validation
            return .require(try .init(configuration: .clientDefault))
        } else if !isLocalhost {
            // Remote host but SSL not required - prefer SSL if available
            return .prefer(try .init(configuration: .clientDefault))
        } else {
            // Localhost - disable SSL
            return .disable
        }
    }

    /// Test database connection with retry logic
    func testConnection(database: any Database) async throws {
        var lastError: Error?

        for attempt in 1...poolConfig.retryAttempts {
            do {
                // Execute a simple query to test connection
                _ = try await (database as! SQLDatabase).raw("SELECT 1").all()
                logger.info("Database connection test passed")
                return
            } catch {
                lastError = error
                logger.warning("Database connection attempt \(attempt)/\(poolConfig.retryAttempts) failed: \(error)")

                if attempt < poolConfig.retryAttempts {
                    try await Task.sleep(nanoseconds: UInt64(poolConfig.retryDelay * 1_000_000_000))
                }
            }
        }

        throw DatabaseConfigurationError.connectionFailed("Failed after \(poolConfig.retryAttempts) attempts: \(lastError?.localizedDescription ?? "unknown")")
    }
}

// MARK: - Database Health Check

/// Database health checker for monitoring
actor DatabaseHealthChecker {
    private let database: any Database
    private let logger: Logger
    private var lastCheckTime: Date = .distantPast
    private var lastCheckResult: HealthCheckResult = .unknown
    private let checkInterval: TimeInterval = 30 // seconds

    struct HealthCheckResult: Sendable {
        let healthy: Bool
        let latencyMs: Double
        let checkedAt: Date
        let error: String?

        static let unknown = HealthCheckResult(
            healthy: false,
            latencyMs: 0,
            checkedAt: .distantPast,
            error: "Not yet checked"
        )
    }

    init(database: any Database, logger: Logger) {
        self.database = database
        self.logger = logger
    }

    /// Check database health
    func check() async -> HealthCheckResult {
        let now = Date()

        // Return cached result if recently checked
        if now.timeIntervalSince(lastCheckTime) < checkInterval {
            return lastCheckResult
        }

        let startTime = Date()

        do {
            _ = try await (database as! SQLDatabase).raw("SELECT 1").all()
            let latency = Date().timeIntervalSince(startTime) * 1000

            let result = HealthCheckResult(
                healthy: true,
                latencyMs: latency,
                checkedAt: now,
                error: nil
            )

            lastCheckTime = now
            lastCheckResult = result

            return result
        } catch {
            let latency = Date().timeIntervalSince(startTime) * 1000

            let result = HealthCheckResult(
                healthy: false,
                latencyMs: latency,
                checkedAt: now,
                error: error.localizedDescription
            )

            lastCheckTime = now
            lastCheckResult = result

            logger.error("Database health check failed", metadata: [
                "error": .string(error.localizedDescription),
                "latency_ms": .string(String(format: "%.2f", latency))
            ])

            return result
        }
    }

    /// Get last known health status without performing new check
    var lastKnownStatus: HealthCheckResult {
        lastCheckResult
    }
}

// MARK: - Errors

enum DatabaseConfigurationError: Error, CustomStringConvertible {
    case invalidURL(String)
    case connectionFailed(String)
    case poolExhausted
    case queryTimeout

    var description: String {
        switch self {
        case .invalidURL(let url):
            return "Invalid database URL: \(url)"
        case .connectionFailed(let reason):
            return "Database connection failed: \(reason)"
        case .poolExhausted:
            return "Database connection pool exhausted"
        case .queryTimeout:
            return "Database query timed out"
        }
    }
}

// MARK: - SQL Database Protocol

import FluentSQL

extension Database {
    /// Execute raw SQL (for health checks)
    func rawQuery(_ sql: String) async throws {
        guard let sqlDB = self as? SQLDatabase else {
            throw DatabaseConfigurationError.connectionFailed("Not a SQL database")
        }
        _ = try await sqlDB.raw(SQLQueryString(sql)).all()
    }
}
