import Foundation

/// Error types for fee calculations
enum FeeCalculationError: Error, CustomStringConvertible {
    case invalidAmount
    case transactionNotBalanced(inputSum: Int, outputSum: Int, fees: Int)
    case insufficientInputs(required: Int, provided: Int)
    
    var description: String {
        switch self {
        case .invalidAmount:
            return "Invalid amount for fee calculation"
        case .transactionNotBalanced(let inputSum, let outputSum, let fees):
            return "Transaction not balanced: inputs=\(inputSum), outputs=\(outputSum), fees=\(fees)"
        case .insufficientInputs(let required, let provided):
            return "Insufficient inputs: required \(required), provided \(provided)"
        }
    }
}

/// Service for fee computation per NUT-02 and NUT-08
struct FeeCalculator: Sendable {
    
    // MARK: - Input Fee Calculation (NUT-02)
    
    /// Calculate total input fees for a batch of proofs
    /// Fee formula: ceil(sum(input_fee_ppk) / 1000)
    /// Where input_fee_ppk comes from each proof's keyset
    func calculateInputFees(proofs: [ProofData], keysets: [String: LoadedKeyset]) -> Int {
        var totalFeePpk = 0
        
        for proof in proofs {
            if let keyset = keysets[proof.id] {
                totalFeePpk += keyset.inputFeePpk
            }
            // If keyset not found, assume 0 fee (validation should have caught this)
        }
        
        // ceil(sum / 1000) - integer ceiling division
        return (totalFeePpk + 999) / 1000
    }
    
    /// Calculate total input fees given keyset info
    func calculateInputFees(proofCount: Int, inputFeePpk: Int) -> Int {
        let totalFeePpk = proofCount * inputFeePpk
        return (totalFeePpk + 999) / 1000
    }
    
    // MARK: - Blank Output Count (NUT-08)
    
    /// Calculate the number of blank outputs needed to return overpaid fees
    /// Formula: max(ceil(log2(fee_reserve)), 1)
    /// This ensures enough outputs to return any amount up to fee_reserve
    func calculateBlankOutputCount(feeReserve: Int) -> Int {
        guard feeReserve > 0 else { return 0 }
        
        // Calculate ceil(log2(fee_reserve))
        // log2(n) = log(n) / log(2)
        // For integer, we can use bit operations
        var count = 0
        var value = feeReserve
        while value > 0 {
            count += 1
            value >>= 1
        }
        
        return max(count, 1)
    }
    
    /// Calculate the amounts needed for blank outputs to return a specific amount
    /// Returns powers of 2 that sum to the amount (binary representation)
    func calculateChangeAmounts(amount: Int) -> [Int] {
        guard amount > 0 else { return [] }
        
        var amounts: [Int] = []
        var remaining = amount
        var power = 0
        
        while remaining > 0 {
            if remaining & 1 == 1 {
                amounts.append(1 << power)
            }
            power += 1
            remaining >>= 1
        }
        
        return amounts.sorted()  // Return in ascending order
    }
    
    // MARK: - Transaction Balance Validation
    
    /// Validate that a swap transaction is balanced
    /// sum(inputs) - fees == sum(outputs)
    func validateSwapBalance(
        inputs: [ProofData],
        outputs: [BlindedMessageData],
        fees: Int
    ) throws {
        let inputSum = inputs.reduce(0) { $0 + $1.amount }
        let outputSum = outputs.reduce(0) { $0 + $1.amount }
        
        let expectedOutputs = inputSum - fees
        
        guard outputSum == expectedOutputs else {
            throw FeeCalculationError.transactionNotBalanced(
                inputSum: inputSum,
                outputSum: outputSum,
                fees: fees
            )
        }
    }
    
    /// Validate that inputs are sufficient for a melt operation
    /// sum(inputs) >= amount + fee_reserve
    func validateMeltInputs(
        inputs: [ProofData],
        amount: Int,
        feeReserve: Int
    ) throws {
        let inputSum = inputs.reduce(0) { $0 + $1.amount }
        let required = amount + feeReserve
        
        guard inputSum >= required else {
            throw FeeCalculationError.insufficientInputs(
                required: required,
                provided: inputSum
            )
        }
    }
    
    /// Validate that outputs sum to the expected amount for minting
    func validateMintOutputs(
        outputs: [BlindedMessageData],
        expectedAmount: Int
    ) throws {
        let outputSum = outputs.reduce(0) { $0 + $1.amount }
        
        guard outputSum == expectedAmount else {
            throw FeeCalculationError.transactionNotBalanced(
                inputSum: expectedAmount,  // The "input" is the payment amount
                outputSum: outputSum,
                fees: 0
            )
        }
    }
    
    // MARK: - Fee Reserve Estimation
    
    /// Estimate fee reserve for a Lightning payment
    /// This is a simple estimation - real implementation should use routing hints
    func estimateFeeReserve(amount: Int, baseFee: Int = 1, feeRate: Double = 0.01) -> Int {
        // Simple formula: baseFee + ceil(amount * feeRate)
        let variableFee = Int(ceil(Double(amount) * feeRate))
        let reserve = baseFee + variableFee
        
        // Minimum reserve of 1 sat
        return max(reserve, 1)
    }
    
    // MARK: - Overpaid Fee Calculation
    
    /// Calculate overpaid amount after a melt operation
    /// overpaid = sum(inputs) - amount - actual_fee_paid - input_fees
    func calculateOverpaidAmount(
        inputSum: Int,
        amount: Int,
        actualFeePaid: Int,
        inputFees: Int
    ) -> Int {
        let overpaid = inputSum - amount - actualFeePaid - inputFees
        return max(overpaid, 0)
    }
}
