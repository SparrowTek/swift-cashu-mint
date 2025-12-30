import Foundation
import Hummingbird
import Logging

// MARK: - Cashu Error Codes (per NUT error_codes.md)

/// Cashu mint error with proper error codes per NUT specification
enum CashuMintError: Error, Sendable {
    // Proof errors (10xxx)
    case blindedMessageAlreadySigned        // 10002
    case tokenCouldNotBeVerified(String)    // 10003
    
    // Transaction errors (11xxx)
    case tokenAlreadySpent                  // 11001
    case transactionNotBalanced(Int, Int)   // 11002 (inputs, outputs)
    case unitNotSupported(String)           // 11005
    case amountOutsideLimit(Int, Int, Int)  // 11006 (amount, min, max)
    case duplicateInputs                    // 11007
    case duplicateOutputs                   // 11008
    case multipleUnits                      // 11009
    case inputOutputUnitMismatch            // 11010
    case amountlessNotSupported             // 11011
    case amountMismatch(Int, Int)           // 11012 (expected, actual)
    
    // Keyset errors (12xxx)
    case keysetUnknown(String)              // 12001
    case keysetInactive(String)             // 12002
    
    // Quote errors (20xxx)
    case quoteNotPaid                       // 20001
    case tokensAlreadyIssued                // 20002
    case mintingDisabled                    // 20003
    case lightningPaymentFailed(String)     // 20004
    case quotePending                       // 20005
    case invoiceAlreadyPaid                 // 20006
    case quoteExpired                       // 20007
    case quoteNotFound(String)              // Custom - quote lookup failed
    
    // Internal errors
    case internalError(String)
    
    /// Error code per NUT specification
    var code: Int {
        switch self {
        case .blindedMessageAlreadySigned:
            return 10002
        case .tokenCouldNotBeVerified:
            return 10003
        case .tokenAlreadySpent:
            return 11001
        case .transactionNotBalanced:
            return 11002
        case .unitNotSupported:
            return 11005
        case .amountOutsideLimit:
            return 11006
        case .duplicateInputs:
            return 11007
        case .duplicateOutputs:
            return 11008
        case .multipleUnits:
            return 11009
        case .inputOutputUnitMismatch:
            return 11010
        case .amountlessNotSupported:
            return 11011
        case .amountMismatch:
            return 11012
        case .keysetUnknown:
            return 12001
        case .keysetInactive:
            return 12002
        case .quoteNotPaid:
            return 20001
        case .tokensAlreadyIssued:
            return 20002
        case .mintingDisabled:
            return 20003
        case .lightningPaymentFailed:
            return 20004
        case .quotePending:
            return 20005
        case .invoiceAlreadyPaid:
            return 20006
        case .quoteExpired:
            return 20007
        case .quoteNotFound:
            return 20001 // Reuse "not paid" code for not found
        case .internalError:
            return 0
        }
    }
    
    /// Human-readable error message
    var detail: String {
        switch self {
        case .blindedMessageAlreadySigned:
            return "Blinded message has already been signed"
        case .tokenCouldNotBeVerified(let reason):
            return "Token could not be verified: \(reason)"
        case .tokenAlreadySpent:
            return "Token is already spent"
        case .transactionNotBalanced(let inputs, let outputs):
            return "Transaction is not balanced: inputs (\(inputs)) != outputs (\(outputs))"
        case .unitNotSupported(let unit):
            return "Unit '\(unit)' is not supported"
        case .amountOutsideLimit(let amount, let min, let max):
            return "Amount \(amount) is outside limit range [\(min), \(max)]"
        case .duplicateInputs:
            return "Duplicate inputs provided"
        case .duplicateOutputs:
            return "Duplicate outputs provided"
        case .multipleUnits:
            return "Inputs or outputs contain multiple units"
        case .inputOutputUnitMismatch:
            return "Inputs and outputs are not of the same unit"
        case .amountlessNotSupported:
            return "Amountless invoices are not supported"
        case .amountMismatch(let expected, let actual):
            return "Amount mismatch: expected \(expected), got \(actual)"
        case .keysetUnknown(let id):
            return "Keyset '\(id)' is not known"
        case .keysetInactive(let id):
            return "Keyset '\(id)' is inactive and cannot sign messages"
        case .quoteNotPaid:
            return "Quote has not been paid"
        case .tokensAlreadyIssued:
            return "Tokens have already been issued for this quote"
        case .quotePending:
            return "Quote is pending"
        case .mintingDisabled:
            return "Minting is currently disabled"
        case .lightningPaymentFailed(let reason):
            return "Lightning payment failed: \(reason)"
        case .invoiceAlreadyPaid:
            return "Invoice has already been paid"
        case .quoteExpired:
            return "Quote has expired"
        case .quoteNotFound(let id):
            return "Quote '\(id)' not found"
        case .internalError(let message):
            return "Internal error: \(message)"
        }
    }
}

// MARK: - HTTP Error Response

/// Cashu error response format per NUT-00
struct CashuErrorResponse: ResponseCodable {
    let detail: String
    let code: Int
}

// MARK: - Error Middleware

/// Middleware that catches errors and formats them per Cashu NUT-00 specification
struct CashuErrorMiddleware<Context: RequestContext>: RouterMiddleware {
    let logger: Logger
    
    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        do {
            return try await next(request, context)
        } catch let error as CashuMintError {
            // Log the error
            logger.warning("Cashu error: \(error.detail)", metadata: [
                "code": .stringConvertible(error.code),
                "path": .string(request.uri.path)
            ])
            
            // Return formatted Cashu error response
            return try createErrorResponse(
                detail: error.detail,
                code: error.code
            )
        } catch let error as DecodingError {
            // Handle JSON decoding errors
            let detail = decodingErrorMessage(error)
            logger.warning("Decoding error: \(detail)", metadata: [
                "path": .string(request.uri.path)
            ])
            
            return try createErrorResponse(
                detail: detail,
                code: 0
            )
        } catch {
            // Log unexpected errors
            logger.error("Unexpected error: \(error)", metadata: [
                "path": .string(request.uri.path),
                "error_type": .string(String(describing: type(of: error)))
            ])
            
            // Return generic error (don't leak internal details)
            return try createErrorResponse(
                detail: "Internal server error",
                code: 0
            )
        }
    }
    
    private func createErrorResponse(detail: String, code: Int) throws -> Response {
        let errorResponse = CashuErrorResponse(detail: detail, code: code)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let body = try encoder.encode(errorResponse)
        
        return Response(
            status: .badRequest,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: body))
        )
    }
    
    private func decodingErrorMessage(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            return "Missing required field: \(key.stringValue)"
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Type mismatch for '\(path)': expected \(type)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Missing value for '\(path)': expected \(type)"
        case .dataCorrupted(let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Invalid data at '\(path)'"
        @unknown default:
            return "Invalid request format"
        }
    }
}

// MARK: - HTTPResponseError Conformance

extension CashuMintError: HTTPResponseError {
    var status: HTTPResponse.Status {
        .badRequest
    }
    
    func response(from request: Request, context: some RequestContext) throws -> Response {
        let errorResponse = CashuErrorResponse(detail: detail, code: code)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(errorResponse)
        
        return Response(
            status: .badRequest,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data))
        )
    }
}
