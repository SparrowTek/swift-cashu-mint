import Foundation
import Logging
import Hummingbird

// MARK: - Structured Log Handler

/// A log handler that outputs structured JSON logs for production environments
struct StructuredLogHandler: LogHandler {
    private let label: String
    private var prettyPrint: Bool

    var logLevel: Logger.Level = .info
    var metadata: Logger.Metadata = [:]

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    init(label: String, prettyPrint: Bool = false) {
        self.label = label
        self.prettyPrint = prettyPrint
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        // Merge metadata
        var mergedMetadata = self.metadata
        if let additionalMetadata = metadata {
            for (key, value) in additionalMetadata {
                mergedMetadata[key] = value
            }
        }

        // Build log entry
        var entry: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "level": level.rawValue.uppercased(),
            "logger": label,
            "message": "\(message)"
        ]

        // Add source info in debug mode
        if level == .debug || level == .trace {
            entry["source"] = [
                "file": URL(fileURLWithPath: file).lastPathComponent,
                "function": function,
                "line": line
            ]
        }

        // Add metadata
        if !mergedMetadata.isEmpty {
            entry["metadata"] = convertMetadata(mergedMetadata)
        }

        // Serialize to JSON
        do {
            let data: Data
            if prettyPrint {
                data = try JSONSerialization.data(
                    withJSONObject: entry,
                    options: [.prettyPrinted, .sortedKeys]
                )
            } else {
                data = try JSONSerialization.data(
                    withJSONObject: entry,
                    options: [.sortedKeys]
                )
            }
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } catch {
            // Fallback to plain text
            print("[\(level.rawValue.uppercased())] \(message)")
        }
    }

    /// Convert Logger.Metadata to a JSON-compatible dictionary
    private func convertMetadata(_ metadata: Logger.Metadata) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in metadata {
            result[key] = convertMetadataValue(value)
        }
        return result
    }

    private func convertMetadataValue(_ value: Logger.Metadata.Value) -> Any {
        switch value {
        case .string(let string):
            return redactSensitive(key: "", value: string)
        case .stringConvertible(let convertible):
            return "\(convertible)"
        case .array(let array):
            return array.map { convertMetadataValue($0) }
        case .dictionary(let dict):
            var result: [String: Any] = [:]
            for (key, val) in dict {
                result[key] = convertMetadataValue(val)
            }
            return result
        }
    }

    /// Redact sensitive values from logs
    private func redactSensitive(key: String, value: String) -> String {
        let sensitivePatterns = [
            "password", "secret", "macaroon", "key", "token",
            "authorization", "credential", "private"
        ]

        let lowercaseKey = key.lowercased()
        for pattern in sensitivePatterns {
            if lowercaseKey.contains(pattern) {
                return "[REDACTED]"
            }
        }

        // Redact values that look like secrets (long hex strings, base64)
        if value.count > 32 && isHexOrBase64(value) {
            return "\(value.prefix(8))...[REDACTED]"
        }

        return value
    }

    private func isHexOrBase64(_ value: String) -> Bool {
        let hexPattern = "^[0-9a-fA-F]+$"
        let base64Pattern = "^[A-Za-z0-9+/=]+$"

        if let regex = try? NSRegularExpression(pattern: hexPattern),
           regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil {
            return true
        }

        if let regex = try? NSRegularExpression(pattern: base64Pattern),
           regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil {
            return true
        }

        return false
    }
}

// MARK: - Log Level Extension

extension Logger.Level {
    var rawValue: String {
        switch self {
        case .trace: return "trace"
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .warning: return "warning"
        case .error: return "error"
        case .critical: return "critical"
        }
    }
}

// MARK: - Request Logging Middleware

/// Middleware that logs all requests with structured data
struct RequestLoggingMiddleware<Context: RequestContext>: RouterMiddleware {
    let logger: Logger

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        let requestId = UUID().uuidString.prefix(8)
        let startTime = Date()

        // Log request start
        logger.info("Request started", metadata: [
            "request_id": .string(String(requestId)),
            "method": .string(String(describing: request.method)),
            "path": .string(request.uri.path),
            "query": .string(request.uri.query ?? "")
        ])

        do {
            let response = try await next(request, context)
            let duration = Date().timeIntervalSince(startTime) * 1000

            // Log successful response
            logger.info("Request completed", metadata: [
                "request_id": .string(String(requestId)),
                "method": .string(String(describing: request.method)),
                "path": .string(request.uri.path),
                "status": .string(String(response.status.code)),
                "duration_ms": .string(String(format: "%.2f", duration))
            ])

            return response
        } catch {
            let duration = Date().timeIntervalSince(startTime) * 1000

            // Log error response
            logger.error("Request failed", metadata: [
                "request_id": .string(String(requestId)),
                "method": .string(String(describing: request.method)),
                "path": .string(request.uri.path),
                "error": .string(String(describing: error)),
                "duration_ms": .string(String(format: "%.2f", duration))
            ])

            throw error
        }
    }
}

// MARK: - Logging Bootstrap

/// Configure logging system based on environment
func configureLogging(verbose: Bool = false, jsonFormat: Bool? = nil) {
    let useJSON = jsonFormat ?? (ProcessInfo.processInfo.environment["LOG_FORMAT"]?.lowercased() == "json")
    let logLevel: Logger.Level = verbose ? .debug : .info

    LoggingSystem.bootstrap { label in
        if useJSON {
            var handler = StructuredLogHandler(label: label)
            handler.logLevel = logLevel
            return handler
        } else {
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = logLevel
            return handler
        }
    }
}

// MARK: - Operation Logger

/// Helper for logging operations with consistent format
struct OperationLogger {
    let logger: Logger
    let operation: String
    let metadata: Logger.Metadata

    init(logger: Logger, operation: String, metadata: Logger.Metadata = [:]) {
        self.logger = logger
        self.operation = operation
        self.metadata = metadata
    }

    func start() {
        var logMetadata = metadata
        logMetadata["operation"] = .string(operation)
        logMetadata["status"] = .string("started")
        logger.info("Operation started", metadata: logMetadata)
    }

    func success(additionalMetadata: Logger.Metadata = [:]) {
        var logMetadata = metadata
        for (key, value) in additionalMetadata {
            logMetadata[key] = value
        }
        logMetadata["operation"] = .string(operation)
        logMetadata["status"] = .string("success")
        logger.info("Operation completed", metadata: logMetadata)
    }

    func failure(error: Error, additionalMetadata: Logger.Metadata = [:]) {
        var logMetadata = metadata
        for (key, value) in additionalMetadata {
            logMetadata[key] = value
        }
        logMetadata["operation"] = .string(operation)
        logMetadata["status"] = .string("failed")
        logMetadata["error"] = .string(String(describing: error))
        logger.error("Operation failed", metadata: logMetadata)
    }
}

// MARK: - Audit Logger

/// Specialized logger for security-relevant events
actor AuditLogger {
    private let logger: Logger

    init(label: String = "swift-cashu-mint.audit") {
        self.logger = Logger(label: label)
    }

    /// Log a mint operation
    func logMint(quoteId: String, amount: Int, outputCount: Int) {
        logger.notice("MINT", metadata: [
            "event": .string("mint_tokens"),
            "quote_id": .string(quoteId),
            "amount": .string(String(amount)),
            "output_count": .string(String(outputCount))
        ])
    }

    /// Log a melt operation
    func logMelt(quoteId: String, amount: Int, feePaid: Int) {
        logger.notice("MELT", metadata: [
            "event": .string("melt_tokens"),
            "quote_id": .string(quoteId),
            "amount": .string(String(amount)),
            "fee_paid": .string(String(feePaid))
        ])
    }

    /// Log a swap operation
    func logSwap(inputSum: Int, outputSum: Int, fees: Int) {
        logger.notice("SWAP", metadata: [
            "event": .string("swap_tokens"),
            "input_sum": .string(String(inputSum)),
            "output_sum": .string(String(outputSum)),
            "fees": .string(String(fees))
        ])
    }

    /// Log a double-spend attempt
    func logDoubleSpendAttempt(proofY: String, clientIP: String?) {
        logger.warning("SECURITY", metadata: [
            "event": .string("double_spend_attempt"),
            "proof_y": .string(proofY.prefix(16) + "..."),
            "client_ip": .string(clientIP ?? "unknown")
        ])
    }

    /// Log a rate limit hit
    func logRateLimitExceeded(clientIP: String, path: String) {
        logger.warning("SECURITY", metadata: [
            "event": .string("rate_limit_exceeded"),
            "client_ip": .string(clientIP),
            "path": .string(path)
        ])
    }

    /// Log an authentication failure
    func logAuthFailure(reason: String, clientIP: String?) {
        logger.warning("SECURITY", metadata: [
            "event": .string("auth_failure"),
            "reason": .string(reason),
            "client_ip": .string(clientIP ?? "unknown")
        ])
    }

    /// Log keyset rotation
    func logKeysetRotation(oldKeysetId: String, newKeysetId: String) {
        logger.notice("KEYSET", metadata: [
            "event": .string("keyset_rotation"),
            "old_keyset_id": .string(oldKeysetId),
            "new_keyset_id": .string(newKeysetId)
        ])
    }
}
