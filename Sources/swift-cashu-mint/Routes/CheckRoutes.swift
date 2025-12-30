import Foundation
import Hummingbird
import Logging

// MARK: - Check Routes (NUT-07)

/// Add check state routes to the router
/// POST /v1/checkstate - Check proof states (UNSPENT, PENDING, SPENT)
func addCheckRoutes<Context: RequestContext>(
    to router: Router<Context>,
    proofValidator: ProofValidator,
    spentProofStore: SpentProofStore,
    logger: Logger
) {
    // POST /v1/checkstate - Check proof states (NUT-07)
    router.post("/v1/checkstate") { request, context in
        let checkRequest = try await request.decode(as: CheckStateRequest.self, context: context)
        
        return try await checkProofStates(
            request: checkRequest,
            proofValidator: proofValidator,
            spentProofStore: spentProofStore,
            logger: logger
        )
    }
}

// MARK: - POST /v1/checkstate (NUT-07)

/// Check the state of proofs by their Y values
private func checkProofStates(
    request: CheckStateRequest,
    proofValidator: ProofValidator,
    spentProofStore: SpentProofStore,
    logger: Logger
) async throws -> CheckStateResponse {
    let ys = request.Ys
    
    // Batch check all Y values
    let states = try await proofValidator.checkSpentStatus(ys)
    
    // Build response in same order as request
    var responses: [ProofStateResponse] = []
    
    for y in ys {
        let state = states[y] ?? .unspent
        
        // Get witness if spent
        var witness: String? = nil
        if state == .spent {
            witness = try await spentProofStore.getWitness(y: y)
        }
        
        responses.append(ProofStateResponse(
            y: y,
            state: state,
            witness: witness
        ))
    }
    
    logger.debug("Check state", metadata: [
        "count": .stringConvertible(ys.count)
    ])
    
    return CheckStateResponse(states: responses)
}

// MARK: - Response Type Extensions

extension CheckStateResponse: ResponseCodable {}
