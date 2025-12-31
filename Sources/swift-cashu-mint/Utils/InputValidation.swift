import Foundation

// MARK: - Input Validation Utilities

/// Validation errors for input data
enum ValidationError: Error, CustomStringConvertible, Sendable {
    case invalidHexString(field: String, value: String)
    case invalidPublicKey(field: String, reason: String)
    case invalidAmount(field: String, value: Int, reason: String)
    case invalidKeysetId(field: String, value: String)
    case invalidQuoteId(value: String)
    case invalidSecret(reason: String)
    case requestTooLarge(maxSize: Int, actualSize: Int)
    case tooManyItems(field: String, max: Int, actual: Int)
    case emptyField(field: String)

    var description: String {
        switch self {
        case .invalidHexString(let field, let value):
            let preview = value.prefix(20)
            return "Invalid hex string for '\(field)': '\(preview)...'"
        case .invalidPublicKey(let field, let reason):
            return "Invalid public key for '\(field)': \(reason)"
        case .invalidAmount(let field, let value, let reason):
            return "Invalid amount for '\(field)': \(value) - \(reason)"
        case .invalidKeysetId(let field, let value):
            return "Invalid keyset ID for '\(field)': '\(value)'"
        case .invalidQuoteId(let value):
            return "Invalid quote ID: '\(value)'"
        case .invalidSecret(let reason):
            return "Invalid secret: \(reason)"
        case .requestTooLarge(let maxSize, let actualSize):
            return "Request too large: \(actualSize) bytes (max \(maxSize))"
        case .tooManyItems(let field, let max, let actual):
            return "Too many items in '\(field)': \(actual) (max \(max))"
        case .emptyField(let field):
            return "Field '\(field)' cannot be empty"
        }
    }
}

// MARK: - Input Validator

/// Centralized input validation for Cashu mint
enum InputValidator {

    // MARK: - Configuration

    /// Maximum request body size in bytes (1 MB)
    static let maxRequestBodySize = 1_048_576

    /// Maximum number of inputs in a swap
    static let maxSwapInputs = 1000

    /// Maximum number of outputs in a swap
    static let maxSwapOutputs = 1000

    /// Maximum secret length
    static let maxSecretLength = 1024

    /// Expected keyset ID length (version prefix + 14 hex chars = 16 chars)
    static let keysetIdLength = 16

    /// Minimum public key length (compressed: 66 hex chars)
    static let minPublicKeyHexLength = 66

    /// Maximum public key length (uncompressed: 130 hex chars)
    static let maxPublicKeyHexLength = 130

    // MARK: - Hex Validation

    /// Validate that a string is valid hexadecimal
    /// - Parameters:
    ///   - hex: The hex string to validate
    ///   - field: Field name for error messages
    /// - Throws: ValidationError if invalid
    static func validateHex(_ hex: String, field: String) throws {
        guard !hex.isEmpty else {
            throw ValidationError.emptyField(field: field)
        }

        // Check length is even (hex pairs)
        guard hex.count % 2 == 0 else {
            throw ValidationError.invalidHexString(field: field, value: hex)
        }

        // Check all characters are valid hex
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard hex.unicodeScalars.allSatisfy({ hexCharacterSet.contains($0) }) else {
            throw ValidationError.invalidHexString(field: field, value: hex)
        }
    }

    /// Convert hex string to Data, validating format
    static func hexToData(_ hex: String, field: String) throws -> Data {
        try validateHex(hex, field: field)

        var data = Data()
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteString = String(hex[index..<nextIndex])
            guard let byte = UInt8(byteString, radix: 16) else {
                throw ValidationError.invalidHexString(field: field, value: hex)
            }
            data.append(byte)
            index = nextIndex
        }

        return data
    }

    // MARK: - Public Key Validation

    /// Validate a compressed or uncompressed public key
    /// - Parameters:
    ///   - pubkeyHex: The public key as hex string
    ///   - field: Field name for error messages
    /// - Throws: ValidationError if invalid
    static func validatePublicKey(_ pubkeyHex: String, field: String) throws {
        // First validate it's valid hex
        try validateHex(pubkeyHex, field: field)

        // Check length (compressed: 33 bytes = 66 hex, uncompressed: 65 bytes = 130 hex)
        guard pubkeyHex.count >= minPublicKeyHexLength else {
            throw ValidationError.invalidPublicKey(
                field: field,
                reason: "Too short: \(pubkeyHex.count) chars (min \(minPublicKeyHexLength))"
            )
        }

        guard pubkeyHex.count <= maxPublicKeyHexLength else {
            throw ValidationError.invalidPublicKey(
                field: field,
                reason: "Too long: \(pubkeyHex.count) chars (max \(maxPublicKeyHexLength))"
            )
        }

        // Check prefix for compressed keys (02 or 03)
        if pubkeyHex.count == minPublicKeyHexLength {
            let prefix = pubkeyHex.prefix(2).lowercased()
            guard prefix == "02" || prefix == "03" else {
                throw ValidationError.invalidPublicKey(
                    field: field,
                    reason: "Invalid compressed key prefix: \(prefix)"
                )
            }
        }

        // Check prefix for uncompressed keys (04)
        if pubkeyHex.count == maxPublicKeyHexLength {
            let prefix = pubkeyHex.prefix(2).lowercased()
            guard prefix == "04" else {
                throw ValidationError.invalidPublicKey(
                    field: field,
                    reason: "Invalid uncompressed key prefix: \(prefix)"
                )
            }
        }
    }

    // MARK: - Amount Validation

    /// Validate an amount value
    /// - Parameters:
    ///   - amount: The amount to validate
    ///   - field: Field name for error messages
    ///   - minAmount: Minimum allowed (inclusive)
    ///   - maxAmount: Maximum allowed (inclusive)
    /// - Throws: ValidationError if invalid
    static func validateAmount(
        _ amount: Int,
        field: String,
        minAmount: Int = 1,
        maxAmount: Int = Int.max
    ) throws {
        guard amount > 0 else {
            throw ValidationError.invalidAmount(
                field: field,
                value: amount,
                reason: "must be positive"
            )
        }

        guard amount >= minAmount else {
            throw ValidationError.invalidAmount(
                field: field,
                value: amount,
                reason: "below minimum (\(minAmount))"
            )
        }

        guard amount <= maxAmount else {
            throw ValidationError.invalidAmount(
                field: field,
                value: amount,
                reason: "above maximum (\(maxAmount))"
            )
        }

        // Check it's a valid power of 2 for token amounts
        // This is optional - some mints may allow non-power-of-2 amounts
    }

    /// Check if amount is a valid power of 2
    static func isPowerOfTwo(_ n: Int) -> Bool {
        n > 0 && (n & (n - 1)) == 0
    }

    // MARK: - Keyset ID Validation

    /// Validate a keyset ID format
    /// - Parameters:
    ///   - keysetId: The keyset ID to validate
    ///   - field: Field name for error messages
    /// - Throws: ValidationError if invalid
    static func validateKeysetId(_ keysetId: String, field: String) throws {
        guard !keysetId.isEmpty else {
            throw ValidationError.emptyField(field: field)
        }

        // Check length (should be 16 hex chars: "00" + 14 chars)
        guard keysetId.count == keysetIdLength else {
            throw ValidationError.invalidKeysetId(field: field, value: keysetId)
        }

        // Must start with version "00"
        guard keysetId.hasPrefix("00") else {
            throw ValidationError.invalidKeysetId(field: field, value: keysetId)
        }

        // Must be valid hex
        try validateHex(keysetId, field: field)
    }

    // MARK: - Quote ID Validation

    /// Validate a quote ID format
    /// Quote IDs should be alphanumeric (base64url-safe characters)
    /// - Parameter quoteId: The quote ID to validate
    /// - Throws: ValidationError if invalid
    static func validateQuoteId(_ quoteId: String) throws {
        guard !quoteId.isEmpty else {
            throw ValidationError.invalidQuoteId(value: quoteId)
        }

        // Reasonable length limits
        guard quoteId.count >= 8 && quoteId.count <= 128 else {
            throw ValidationError.invalidQuoteId(value: quoteId)
        }

        // Alphanumeric plus base64url safe characters (- and _)
        let allowedCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard quoteId.unicodeScalars.allSatisfy({ allowedCharacterSet.contains($0) }) else {
            throw ValidationError.invalidQuoteId(value: quoteId)
        }
    }

    // MARK: - Secret Validation

    /// Validate a proof secret
    /// - Parameter secret: The secret string
    /// - Throws: ValidationError if invalid
    static func validateSecret(_ secret: String) throws {
        guard !secret.isEmpty else {
            throw ValidationError.invalidSecret(reason: "cannot be empty")
        }

        guard secret.count <= maxSecretLength else {
            throw ValidationError.invalidSecret(reason: "too long (\(secret.count) chars, max \(maxSecretLength))")
        }

        // Secrets can be plain strings or JSON (for spending conditions)
        // We just validate basic safety - no null bytes or control characters
        let dangerousCharacterSet = CharacterSet.controlCharacters.subtracting(CharacterSet.whitespacesAndNewlines)
        guard !secret.unicodeScalars.contains(where: { dangerousCharacterSet.contains($0) }) else {
            throw ValidationError.invalidSecret(reason: "contains invalid control characters")
        }
    }

    // MARK: - Collection Size Validation

    /// Validate collection size limits
    static func validateCollectionSize<T>(_ items: [T], field: String, maxItems: Int) throws {
        guard items.count <= maxItems else {
            throw ValidationError.tooManyItems(field: field, max: maxItems, actual: items.count)
        }
    }

    // MARK: - Proof Validation

    /// Validate a proof's format (not cryptographic validity)
    static func validateProofFormat(_ proof: ProofData) throws {
        try validateAmount(proof.amount, field: "proof.amount")
        try validateKeysetId(proof.id, field: "proof.id")
        try validateSecret(proof.secret)
        try validatePublicKey(proof.C, field: "proof.C")
    }

    /// Validate all proofs in a collection
    static func validateProofsFormat(_ proofs: [ProofData]) throws {
        try validateCollectionSize(proofs, field: "inputs", maxItems: maxSwapInputs)

        for (index, proof) in proofs.enumerated() {
            do {
                try validateProofFormat(proof)
            } catch let error as ValidationError {
                // Add index context
                throw ValidationError.invalidAmount(
                    field: "inputs[\(index)]",
                    value: proof.amount,
                    reason: error.description
                )
            }
        }
    }

    // MARK: - Blinded Message Validation

    /// Validate a blinded message's format
    static func validateBlindedMessageFormat(_ message: BlindedMessageData) throws {
        try validateAmount(message.amount, field: "output.amount")
        try validateKeysetId(message.id, field: "output.id")
        try validatePublicKey(message.B_, field: "output.B_")
    }

    /// Validate all blinded messages in a collection
    static func validateBlindedMessagesFormat(_ messages: [BlindedMessageData]) throws {
        try validateCollectionSize(messages, field: "outputs", maxItems: maxSwapOutputs)

        for (index, message) in messages.enumerated() {
            do {
                try validateBlindedMessageFormat(message)
            } catch let error as ValidationError {
                throw ValidationError.invalidAmount(
                    field: "outputs[\(index)]",
                    value: message.amount,
                    reason: error.description
                )
            }
        }
    }
}

// MARK: - Middleware Integration

import Hummingbird

/// Request size limiting middleware
struct RequestSizeLimitMiddleware<Context: RequestContext>: RouterMiddleware {
    let maxSize: Int

    init(maxSize: Int = InputValidator.maxRequestBodySize) {
        self.maxSize = maxSize
    }

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        // Check Content-Length header if present
        if let contentLength = request.headers[.contentLength],
           let length = Int(contentLength),
           length > maxSize {
            throw CashuMintError.internalError("Request too large: \(length) bytes (max \(maxSize))")
        }

        return try await next(request, context)
    }
}

// MARK: - CashuMintError Extension

extension CashuMintError {
    /// Create a CashuMintError from a ValidationError
    static func from(_ validationError: ValidationError) -> CashuMintError {
        switch validationError {
        case .invalidHexString(let field, _):
            return .tokenCouldNotBeVerified("Invalid hex in \(field)")
        case .invalidPublicKey(let field, let reason):
            return .tokenCouldNotBeVerified("Invalid public key in \(field): \(reason)")
        case .invalidAmount(_, let value, _):
            return .amountOutsideLimit(value, 1, Int.max)
        case .invalidKeysetId(_, let value):
            return .keysetUnknown(value)
        case .invalidQuoteId(let value):
            return .quoteNotFound(value)
        case .invalidSecret(let reason):
            return .tokenCouldNotBeVerified("Invalid secret: \(reason)")
        case .requestTooLarge:
            return .internalError(validationError.description)
        case .tooManyItems(let field, let max, _):
            return .internalError("Too many \(field) (max \(max))")
        case .emptyField(let field):
            return .tokenCouldNotBeVerified("Empty field: \(field)")
        }
    }
}
