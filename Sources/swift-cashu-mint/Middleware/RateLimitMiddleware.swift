import Foundation
import Hummingbird
import Logging

// MARK: - Rate Limit Configuration

/// Configuration for rate limiting
struct RateLimitConfiguration: Sendable {
    /// Maximum requests per window
    let maxRequests: Int

    /// Window duration in seconds
    let windowSeconds: TimeInterval

    /// Endpoints with custom limits (path prefix -> limit)
    let customLimits: [String: Int]

    /// Endpoints to exclude from rate limiting
    let excludedPaths: Set<String>

    /// Default configuration
    static let `default` = RateLimitConfiguration(
        maxRequests: 100,
        windowSeconds: 60,
        customLimits: [
            "/v1/swap": 30,           // More restrictive for swaps
            "/v1/mint/bolt11": 20,    // More restrictive for minting
            "/v1/melt/bolt11": 20     // More restrictive for melting
        ],
        excludedPaths: ["/health", "/"]
    )

    /// Stricter configuration for production
    static let strict = RateLimitConfiguration(
        maxRequests: 60,
        windowSeconds: 60,
        customLimits: [
            "/v1/swap": 20,
            "/v1/mint/bolt11": 10,
            "/v1/melt/bolt11": 10
        ],
        excludedPaths: ["/health", "/"]
    )
}

// MARK: - Rate Limit Store

/// Thread-safe store for tracking request counts per client
actor RateLimitStore {
    /// Request count and window expiry per client identifier
    private var clients: [String: ClientState] = [:]

    /// Cleanup interval tracking
    private var lastCleanup: Date = Date()
    private let cleanupInterval: TimeInterval = 300 // 5 minutes

    struct ClientState {
        var requestCount: Int
        var windowExpiry: Date
    }

    /// Check if request should be allowed and increment counter
    /// Returns (allowed, currentCount, limit, retryAfterSeconds)
    func checkAndIncrement(
        clientId: String,
        limit: Int,
        windowSeconds: TimeInterval
    ) -> (allowed: Bool, currentCount: Int, limit: Int, retryAfter: Int?) {
        let now = Date()

        // Periodic cleanup of expired entries
        if now.timeIntervalSince(lastCleanup) > cleanupInterval {
            cleanupExpiredEntries(now: now)
            lastCleanup = now
        }

        // Get or create client state
        var state = clients[clientId] ?? ClientState(
            requestCount: 0,
            windowExpiry: now.addingTimeInterval(windowSeconds)
        )

        // Check if window has expired
        if now >= state.windowExpiry {
            // Reset window
            state = ClientState(
                requestCount: 0,
                windowExpiry: now.addingTimeInterval(windowSeconds)
            )
        }

        // Check if limit exceeded
        if state.requestCount >= limit {
            let retryAfter = Int(state.windowExpiry.timeIntervalSince(now).rounded(.up))
            return (false, state.requestCount, limit, max(1, retryAfter))
        }

        // Increment and store
        state.requestCount += 1
        clients[clientId] = state

        return (true, state.requestCount, limit, nil)
    }

    /// Get current state for a client (for headers)
    func getState(clientId: String) -> (count: Int, remaining: Int, resetAt: Date)? {
        guard let state = clients[clientId] else { return nil }
        return (state.requestCount, max(0, 100 - state.requestCount), state.windowExpiry)
    }

    /// Remove expired entries to prevent memory growth
    private func cleanupExpiredEntries(now: Date) {
        clients = clients.filter { _, state in
            state.windowExpiry > now
        }
    }

    /// Get current number of tracked clients (for monitoring)
    var clientCount: Int {
        clients.count
    }
}

// MARK: - Rate Limit Error

/// Error returned when rate limit is exceeded
struct RateLimitExceededError: Error, HTTPResponseError {
    let retryAfter: Int
    let limit: Int
    let currentCount: Int

    var status: HTTPResponse.Status {
        .tooManyRequests
    }

    func response(from request: Request, context: some RequestContext) throws -> Response {
        let body = """
        {"detail": "Rate limit exceeded. Try again in \(retryAfter) seconds.", "code": 429}
        """

        return Response(
            status: .tooManyRequests,
            headers: [
                .contentType: "application/json",
                .init("Retry-After")!: String(retryAfter),
                .init("X-RateLimit-Limit")!: String(limit),
                .init("X-RateLimit-Remaining")!: "0",
                .init("X-RateLimit-Reset")!: String(Int(Date().timeIntervalSince1970) + retryAfter)
            ],
            body: .init(byteBuffer: .init(string: body))
        )
    }
}

// MARK: - Rate Limit Middleware

/// Middleware that enforces per-client rate limiting
struct RateLimitMiddleware<Context: RequestContext>: RouterMiddleware {
    let store: RateLimitStore
    let config: RateLimitConfiguration
    let logger: Logger

    init(
        store: RateLimitStore = RateLimitStore(),
        config: RateLimitConfiguration = .default,
        logger: Logger
    ) {
        self.store = store
        self.config = config
        self.logger = logger
    }

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        let path = request.uri.path

        // Skip excluded paths
        if config.excludedPaths.contains(path) {
            return try await next(request, context)
        }

        // Get client identifier (IP address)
        let clientId = extractClientId(from: request)

        // Determine limit for this endpoint
        let limit = determineLimit(for: path)

        // Check rate limit
        let (allowed, currentCount, effectiveLimit, retryAfter) = await store.checkAndIncrement(
            clientId: clientId,
            limit: limit,
            windowSeconds: config.windowSeconds
        )

        if !allowed {
            logger.warning("Rate limit exceeded", metadata: [
                "client": .string(clientId),
                "path": .string(path),
                "count": .stringConvertible(currentCount),
                "limit": .stringConvertible(effectiveLimit)
            ])

            throw RateLimitExceededError(
                retryAfter: retryAfter ?? 60,
                limit: effectiveLimit,
                currentCount: currentCount
            )
        }

        // Process request
        var response = try await next(request, context)

        // Add rate limit headers to response
        let remaining = max(0, effectiveLimit - currentCount)
        let resetTimestamp = Int(Date().timeIntervalSince1970) + Int(config.windowSeconds)

        response.headers[.init("X-RateLimit-Limit")!] = String(effectiveLimit)
        response.headers[.init("X-RateLimit-Remaining")!] = String(remaining)
        response.headers[.init("X-RateLimit-Reset")!] = String(resetTimestamp)

        return response
    }

    /// Extract client identifier from request
    /// Checks X-Forwarded-For, X-Real-IP, then falls back to connection address
    private func extractClientId(from request: Request) -> String {
        // Check X-Forwarded-For (may contain multiple IPs, take the first)
        if let forwardedFor = request.headers[.init("X-Forwarded-For")!],
           let firstIP = forwardedFor.split(separator: ",").first {
            return String(firstIP).trimmingCharacters(in: .whitespaces)
        }

        // Check X-Real-IP
        if let realIP = request.headers[.init("X-Real-IP")!] {
            return realIP
        }

        // Fall back to a default (in production, you'd get the actual connection IP)
        // Hummingbird doesn't expose connection address directly in Request
        // so we use a combination of headers or a default
        return "unknown"
    }

    /// Determine the rate limit for a given path
    private func determineLimit(for path: String) -> Int {
        // Check for exact match first
        if let limit = config.customLimits[path] {
            return limit
        }

        // Check for prefix match
        for (prefix, limit) in config.customLimits {
            if path.hasPrefix(prefix) {
                return limit
            }
        }

        // Return default limit
        return config.maxRequests
    }
}

// MARK: - Rate Limit Configuration Extension

extension MintConfiguration {
    /// Create rate limit configuration from environment
    var rateLimitConfig: RateLimitConfiguration {
        let maxRequests = Int(ProcessInfo.processInfo.environment["RATE_LIMIT_MAX_REQUESTS"] ?? "100") ?? 100
        let windowSeconds = TimeInterval(ProcessInfo.processInfo.environment["RATE_LIMIT_WINDOW_SECONDS"] ?? "60") ?? 60

        return RateLimitConfiguration(
            maxRequests: maxRequests,
            windowSeconds: windowSeconds,
            customLimits: [
                "/v1/swap": maxRequests / 3,
                "/v1/mint/bolt11": maxRequests / 5,
                "/v1/melt/bolt11": maxRequests / 5
            ],
            excludedPaths: ["/health", "/"]
        )
    }
}
