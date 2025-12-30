import Foundation

/// Request for POST /v1/swap (NUT-03)
struct SwapRequest: Codable, Sendable {
    /// Proofs to spend (inputs)
    let inputs: [ProofData]
    
    /// Blinded messages to sign (outputs)
    let outputs: [BlindedMessageData]
}

/// Response for POST /v1/swap (NUT-03)
struct SwapResponse: Codable, Sendable {
    /// Blind signatures for the outputs
    let signatures: [BlindSignatureData]
}
