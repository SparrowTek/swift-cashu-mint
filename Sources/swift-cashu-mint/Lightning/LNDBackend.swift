import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// LND Lightning backend using the REST API
/// Connects to an LND node via its REST interface
actor LNDBackend: LightningBackend {
    
    /// Base URL for the LND REST API
    private let baseURL: URL
    
    /// Macaroon for authentication (hex encoded)
    private let macaroon: String
    
    /// URLSession for making requests
    private let session: URLSession
    
    /// JSON decoder configured for LND responses
    private let decoder: JSONDecoder
    
    /// JSON encoder for requests
    private let encoder: JSONEncoder
    
    /// Initialize with LND connection details
    /// - Parameters:
    ///   - host: LND REST API host (e.g., "localhost:8080")
    ///   - macaroonPath: Path to the macaroon file
    ///   - certPath: Optional path to the TLS certificate (for self-signed certs)
    init(host: String, macaroonPath: String, certPath: String? = nil) throws {
        // Parse host into URL
        let urlString = host.hasPrefix("http") ? host : "https://\(host)"
        guard let url = URL(string: urlString) else {
            throw LightningError.connectionFailed("Invalid host URL: \(host)")
        }
        self.baseURL = url
        
        // Read macaroon file
        let macaroonData = try Data(contentsOf: URL(fileURLWithPath: macaroonPath))
        self.macaroon = macaroonData.map { String(format: "%02x", $0) }.joined()
        
        // Configure URLSession
        // Note: In production, you'd want to properly handle TLS certificate validation
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        
        self.session = URLSession(configuration: config)
        
        // Configure JSON decoder/encoder
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }
    
    /// Initialize with pre-loaded macaroon (for testing or when macaroon is in env var)
    init(host: String, macaroonHex: String) throws {
        let urlString = host.hasPrefix("http") ? host : "https://\(host)"
        guard let url = URL(string: urlString) else {
            throw LightningError.connectionFailed("Invalid host URL: \(host)")
        }
        self.baseURL = url
        self.macaroon = macaroonHex
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }
    
    // MARK: - Invoice Creation
    
    func createInvoice(amountSat: Int, memo: String?, expirySecs: Int) async throws -> CreateInvoiceResult {
        let request = LNDAddInvoiceRequest(
            value: String(amountSat),
            memo: memo ?? "",
            expiry: String(expirySecs)
        )
        
        let response: LNDAddInvoiceResponse = try await post(
            endpoint: "/v1/invoices",
            body: request
        )
        
        // Calculate expiry date
        let expiry = Date().addingTimeInterval(TimeInterval(expirySecs))
        
        return CreateInvoiceResult(
            bolt11: response.paymentRequest,
            paymentHash: response.rHashStr,
            expiry: expiry
        )
    }
    
    // MARK: - Invoice Status
    
    func getInvoiceStatus(paymentHash: String) async throws -> InvoiceStatus {
        // LND uses base64-encoded payment hash in URL
        guard let hashData = Data(hexString: paymentHash) else {
            throw LightningError.invoiceNotFound(paymentHash)
        }
        let base64Hash = hashData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let response: LNDInvoice = try await get(
            endpoint: "/v1/invoice/\(base64Hash)"
        )
        
        return mapInvoiceState(response.state)
    }
    
    func isInvoicePaid(paymentHash: String) async throws -> Bool {
        let status = try await getInvoiceStatus(paymentHash: paymentHash)
        return status == .paid
    }
    
    // MARK: - Invoice Decoding
    
    func decodeInvoice(bolt11: String) async throws -> DecodedInvoice {
        let response: LNDPayReq = try await get(
            endpoint: "/v1/payreq/\(bolt11)"
        )
        
        // Parse expiry
        let timestamp = Int64(response.timestamp) ?? 0
        let expirySeconds = Int64(response.expiry) ?? 3600
        let expiry = Date(timeIntervalSince1970: TimeInterval(timestamp + expirySeconds))
        
        return DecodedInvoice(
            paymentHash: response.paymentHash,
            amountMsat: (Int64(response.numSatoshis) ?? 0) * 1000,
            description: response.description.isEmpty ? nil : response.description,
            expiry: expiry,
            destination: response.destination,
            bolt11: bolt11
        )
    }
    
    // MARK: - Payment
    
    func payInvoice(bolt11: String, maxFeeSat: Int, timeoutSecs: Int) async throws -> PaymentResult {
        let request = LNDSendPaymentRequest(
            paymentRequest: bolt11,
            feeLimitSat: String(maxFeeSat),
            timeoutSeconds: timeoutSecs
        )
        
        do {
            let response: LNDSendResponse = try await post(
                endpoint: "/v1/channels/transactions",
                body: request
            )
            
            if let error = response.paymentError, !error.isEmpty {
                return PaymentResult(
                    status: .failed,
                    preimage: nil,
                    feeSat: nil,
                    feeMsat: nil,
                    error: error
                )
            }
            
            let feeMsat = Int64(response.paymentRoute?.totalFeesMsat ?? "0") ?? 0
            
            return PaymentResult(
                status: .succeeded,
                preimage: response.paymentPreimage,
                feeSat: Int(feeMsat / 1000),
                feeMsat: feeMsat,
                error: nil
            )
        } catch let error as LightningError {
            throw error
        } catch {
            return PaymentResult(
                status: .failed,
                preimage: nil,
                feeSat: nil,
                feeMsat: nil,
                error: error.localizedDescription
            )
        }
    }
    
    func getPaymentStatus(paymentHash: String) async throws -> PaymentResult {
        // LND uses base64-encoded payment hash
        guard let hashData = Data(hexString: paymentHash) else {
            return PaymentResult(
                status: .pending,
                preimage: nil,
                feeSat: nil,
                feeMsat: nil,
                error: nil
            )
        }
        let base64Hash = hashData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let response: LNDPaymentStatus = try await get(
            endpoint: "/v1/payments/\(base64Hash)"
        )
        
        guard let payment = response.payments.first else {
            return PaymentResult(
                status: .pending,
                preimage: nil,
                feeSat: nil,
                feeMsat: nil,
                error: nil
            )
        }
        
        let status: PaymentStatus
        switch payment.status {
        case "SUCCEEDED":
            status = .succeeded
        case "FAILED":
            status = .failed
        default:
            status = .pending
        }
        
        let feeMsat = Int64(payment.feeMsat ?? "0") ?? 0
        
        return PaymentResult(
            status: status,
            preimage: payment.paymentPreimage,
            feeSat: Int(feeMsat / 1000),
            feeMsat: feeMsat,
            error: payment.failureReason
        )
    }
    
    // MARK: - Node Info
    
    func getNodePubkey() async throws -> String {
        let response: LNDGetInfoResponse = try await get(endpoint: "/v1/getinfo")
        return response.identityPubkey
    }
    
    func isReady() async throws -> Bool {
        do {
            let response: LNDGetInfoResponse = try await get(endpoint: "/v1/getinfo")
            return response.syncedToChain
        } catch {
            return false
        }
    }
    
    func getBalance() async throws -> Int {
        let response: LNDChannelBalance = try await get(endpoint: "/v1/balance/channels")
        return Int(response.localBalance?.sat ?? "0") ?? 0
    }
    
    // MARK: - HTTP Helpers
    
    private func get<T: Decodable>(endpoint: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "GET"
        request.setValue(macaroon, forHTTPHeaderField: "Grpc-Metadata-macaroon")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LightningError.connectionFailed("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? decoder.decode(LNDErrorResponse.self, from: data) {
                throw LightningError.connectionFailed(errorResponse.message)
            }
            throw LightningError.connectionFailed("HTTP \(httpResponse.statusCode)")
        }
        
        return try decoder.decode(T.self, from: data)
    }
    
    private func post<T: Decodable, B: Encodable>(endpoint: String, body: B) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue(macaroon, forHTTPHeaderField: "Grpc-Metadata-macaroon")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LightningError.connectionFailed("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? decoder.decode(LNDErrorResponse.self, from: data) {
                throw LightningError.connectionFailed(errorResponse.message)
            }
            throw LightningError.connectionFailed("HTTP \(httpResponse.statusCode)")
        }
        
        return try decoder.decode(T.self, from: data)
    }
    
    // MARK: - State Mapping
    
    private func mapInvoiceState(_ state: String) -> InvoiceStatus {
        switch state {
        case "SETTLED":
            return .paid
        case "CANCELED":
            return .cancelled
        case "ACCEPTED":
            return .pending
        default:
            return .pending
        }
    }
}

// MARK: - LND API Request/Response Types

private struct LNDAddInvoiceRequest: Encodable {
    let value: String
    let memo: String
    let expiry: String
}

private struct LNDAddInvoiceResponse: Decodable {
    let rHash: String?
    let rHashStr: String
    let paymentRequest: String
    let addIndex: String?
    
    enum CodingKeys: String, CodingKey {
        case rHash = "r_hash"
        case rHashStr = "r_hash_str"
        case paymentRequest = "payment_request"
        case addIndex = "add_index"
    }
}

private struct LNDInvoice: Decodable {
    let rHash: String?
    let state: String
    let amtPaidSat: String?
    let settleDate: String?
    
    enum CodingKeys: String, CodingKey {
        case rHash = "r_hash"
        case state
        case amtPaidSat = "amt_paid_sat"
        case settleDate = "settle_date"
    }
}

private struct LNDPayReq: Decodable {
    let destination: String
    let paymentHash: String
    let numSatoshis: String
    let timestamp: String
    let expiry: String
    let description: String
    
    enum CodingKeys: String, CodingKey {
        case destination
        case paymentHash = "payment_hash"
        case numSatoshis = "num_satoshis"
        case timestamp
        case expiry
        case description
    }
}

private struct LNDSendPaymentRequest: Encodable {
    let paymentRequest: String
    let feeLimitSat: String
    let timeoutSeconds: Int
    
    enum CodingKeys: String, CodingKey {
        case paymentRequest = "payment_request"
        case feeLimitSat = "fee_limit_sat"
        case timeoutSeconds = "timeout_seconds"
    }
}

private struct LNDSendResponse: Decodable {
    let paymentError: String?
    let paymentPreimage: String?
    let paymentRoute: LNDRoute?
    
    enum CodingKeys: String, CodingKey {
        case paymentError = "payment_error"
        case paymentPreimage = "payment_preimage"
        case paymentRoute = "payment_route"
    }
}

private struct LNDRoute: Decodable {
    let totalFeesMsat: String?
    
    enum CodingKeys: String, CodingKey {
        case totalFeesMsat = "total_fees_msat"
    }
}

private struct LNDPaymentStatus: Decodable {
    let payments: [LNDPayment]
}

private struct LNDPayment: Decodable {
    let status: String
    let paymentPreimage: String?
    let feeMsat: String?
    let failureReason: String?
    
    enum CodingKeys: String, CodingKey {
        case status
        case paymentPreimage = "payment_preimage"
        case feeMsat = "fee_msat"
        case failureReason = "failure_reason"
    }
}

private struct LNDGetInfoResponse: Decodable {
    let identityPubkey: String
    let syncedToChain: Bool
    let blockHeight: Int?
    
    enum CodingKeys: String, CodingKey {
        case identityPubkey = "identity_pubkey"
        case syncedToChain = "synced_to_chain"
        case blockHeight = "block_height"
    }
}

private struct LNDChannelBalance: Decodable {
    let localBalance: LNDAmount?
    let remoteBalance: LNDAmount?
    
    enum CodingKeys: String, CodingKey {
        case localBalance = "local_balance"
        case remoteBalance = "remote_balance"
    }
}

private struct LNDAmount: Decodable {
    let sat: String?
    let msat: String?
}

private struct LNDErrorResponse: Decodable {
    let message: String
    let code: Int?
}
