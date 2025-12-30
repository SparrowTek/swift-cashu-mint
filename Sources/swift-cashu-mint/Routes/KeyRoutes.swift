import Foundation
import Hummingbird
import Logging

// MARK: - Key Routes (NUT-01, NUT-02)

/// Add key routes to the router
/// - NUT-01: GET /v1/keys - Return all active keysets with their public keys
/// - NUT-02: GET /v1/keysets - Return all keysets (active and inactive)
/// - NUT-02: GET /v1/keys/{keyset_id} - Return specific keyset by ID
func addKeyRoutes(
    to router: Router<some RequestContext>,
    keysetManager: KeysetManager,
    logger: Logger
) {
    // GET /v1/keys - Return all active keysets with their public keys (NUT-01)
    router.get("/v1/keys") { _, _ in
        try await getActiveKeys(keysetManager: keysetManager)
    }
    
    // GET /v1/keys/:keyset_id - Return specific keyset by ID (NUT-02)
    router.get("/v1/keys/{keyset_id}") { request, context in
        let keysetId = context.parameters.get("keyset_id") ?? ""
        guard !keysetId.isEmpty else {
            throw CashuMintError.keysetUnknown("")
        }
        return try await getKeysetById(keysetId, keysetManager: keysetManager)
    }
    
    // GET /v1/keysets - Return all keysets (active and inactive) (NUT-02)
    router.get("/v1/keysets") { _, _ in
        try await getAllKeysets(keysetManager: keysetManager)
    }
}

// MARK: - GET /v1/keys (NUT-01)

/// Returns all active keysets with their public keys
private func getActiveKeys(keysetManager: KeysetManager) async throws -> GetKeysResponse {
    let activeKeysets = try await keysetManager.getActiveKeysetsWithKeys()
    
    let keysetResponses = activeKeysets.map { keyset in
        // Convert Int-keyed dictionary to String-keyed for JSON
        let stringKeys = Dictionary(
            uniqueKeysWithValues: keyset.publicKeys.map { (String($0.key), $0.value) }
        )
        return KeysetResponse(
            id: keyset.id,
            unit: keyset.unit,
            keys: stringKeys
        )
    }
    
    return GetKeysResponse(keysets: keysetResponses)
}

// MARK: - GET /v1/keys/:keyset_id (NUT-02)

/// Returns a specific keyset by ID
private func getKeysetById(_ keysetId: String, keysetManager: KeysetManager) async throws -> GetKeysResponse {
    do {
        let keyset = try await keysetManager.getKeyset(id: keysetId)
        
        // Convert Int-keyed dictionary to String-keyed for JSON
        let stringKeys = Dictionary(
            uniqueKeysWithValues: keyset.publicKeys.map { (String($0.key), $0.value) }
        )
        
        let keysetResponse = KeysetResponse(
            id: keyset.id,
            unit: keyset.unit,
            keys: stringKeys
        )
        
        return GetKeysResponse(keysets: [keysetResponse])
    } catch is KeysetManagerError {
        throw CashuMintError.keysetUnknown(keysetId)
    }
}

// MARK: - GET /v1/keysets (NUT-02)

/// Returns all keysets (active and inactive) without full public keys
private func getAllKeysets(keysetManager: KeysetManager) async throws -> GetKeysetsResponse {
    let keysets = try await keysetManager.getAllKeysets()
    
    let keysetInfos = keysets.map { keyset in
        KeysetInfo(
            id: keyset.id,
            unit: keyset.unit,
            active: keyset.active,
            inputFeePpk: keyset.inputFeePpk
        )
    }
    
    return GetKeysetsResponse(keysets: keysetInfos)
}
