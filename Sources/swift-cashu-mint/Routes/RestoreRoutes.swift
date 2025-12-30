import Foundation
import Hummingbird
import Logging

// MARK: - Restore Routes (NUT-09)

/// Add restore routes to the router
/// POST /v1/restore - Restore blind signatures for wallet recovery
func addRestoreRoutes<Context: RequestContext>(
    to router: Router<Context>,
    signingService: SigningService,
    logger: Logger
) {
    // POST /v1/restore - Restore blind signatures (NUT-09)
    router.post("/v1/restore") { request, context in
        let restoreRequest = try await request.decode(as: RestoreRequest.self, context: context)
        
        return try await restoreSignatures(
            request: restoreRequest,
            signingService: signingService,
            logger: logger
        )
    }
}

// MARK: - POST /v1/restore (NUT-09)

/// Restore previously issued blind signatures for wallet recovery
private func restoreSignatures(
    request: RestoreRequest,
    signingService: SigningService,
    logger: Logger
) async throws -> RestoreResponse {
    let outputs = request.outputs
    
    // Look up stored signatures for the provided blinded messages
    let (foundOutputs, foundSignatures) = try await signingService.getStoredSignatures(for: outputs)
    
    logger.debug("Restore signatures", metadata: [
        "requested": .stringConvertible(outputs.count),
        "found": .stringConvertible(foundOutputs.count)
    ])
    
    return RestoreResponse(outputs: foundOutputs, signatures: foundSignatures)
}

// MARK: - Response Type Extensions

extension RestoreResponse: ResponseCodable {}
