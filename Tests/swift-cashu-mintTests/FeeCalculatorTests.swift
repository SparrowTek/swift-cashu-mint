import Testing
@testable import swift_cashu_mint

@Suite("FeeCalculator Tests")
struct FeeCalculatorTests {
    
    let calculator = FeeCalculator()
    
    // MARK: - Input Fee Calculation Tests (NUT-02)
    
    @Test("Zero fees for zero proofs")
    func zeroFeesForZeroProofs() {
        let fee = calculator.calculateInputFees(proofCount: 0, inputFeePpk: 100)
        #expect(fee == 0)
    }
    
    @Test("Zero fees when inputFeePpk is zero")
    func zeroFeesWhenPpkIsZero() {
        let fee = calculator.calculateInputFees(proofCount: 10, inputFeePpk: 0)
        #expect(fee == 0)
    }
    
    @Test("Fee calculation with single proof - 100 ppk rounds up to 1")
    func singleProofFee() {
        // 1 proof * 100 ppk = 100 ppk = 0.1 sat, rounds up to 1 sat
        let fee = calculator.calculateInputFees(proofCount: 1, inputFeePpk: 100)
        #expect(fee == 1)
    }
    
    @Test("Fee calculation matches NUT-02 example - 3 proofs with 100 ppk")
    func nut02ExampleFee() {
        // NUT-02 example: 3 proofs * 100 ppk = 300 ppk = 0.3 sat, rounds up to 1 sat
        let fee = calculator.calculateInputFees(proofCount: 3, inputFeePpk: 100)
        #expect(fee == 1)
    }
    
    @Test("Fee rounds up correctly - 10 proofs at 100 ppk")
    func tenProofsFeeRoundsUp() {
        // 10 proofs * 100 ppk = 1000 ppk = 1 sat exactly
        let fee = calculator.calculateInputFees(proofCount: 10, inputFeePpk: 100)
        #expect(fee == 1)
    }
    
    @Test("Fee rounds up correctly - 11 proofs at 100 ppk")
    func elevenProofsFeeRoundsUp() {
        // 11 proofs * 100 ppk = 1100 ppk = 1.1 sat, rounds up to 2 sat
        let fee = calculator.calculateInputFees(proofCount: 11, inputFeePpk: 100)
        #expect(fee == 2)
    }
    
    @Test("Fee calculation with 20 proofs at 100 ppk")
    func twentyProofsFee() {
        // 20 proofs * 100 ppk = 2000 ppk = 2 sat exactly
        let fee = calculator.calculateInputFees(proofCount: 20, inputFeePpk: 100)
        #expect(fee == 2)
    }
    
    @Test("Fee calculation with high ppk - 1000 ppk means 1 sat per proof")
    func highPpkFee() {
        // 1000 ppk = 1 sat per proof
        let fee = calculator.calculateInputFees(proofCount: 5, inputFeePpk: 1000)
        #expect(fee == 5)
    }
    
    @Test("Fee calculation with very small ppk - 1 ppk")
    func verySmallPpkFee() {
        // 100 proofs * 1 ppk = 100 ppk = 0.1 sat, rounds up to 1 sat
        let fee = calculator.calculateInputFees(proofCount: 100, inputFeePpk: 1)
        #expect(fee == 1)
    }
    
    @Test("Fee calculation ceiling - 999 ppk rounds up to 1")
    func feeCeiling999() {
        // 999 ppk rounds up to 1 sat
        let fee = calculator.calculateInputFees(proofCount: 1, inputFeePpk: 999)
        #expect(fee == 1)
    }
    
    @Test("Fee calculation ceiling - 1001 ppk rounds up to 2")
    func feeCeiling1001() {
        // 1001 ppk rounds up to 2 sat
        let fee = calculator.calculateInputFees(proofCount: 1, inputFeePpk: 1001)
        #expect(fee == 2)
    }
    
    // MARK: - Blank Output Count Tests (NUT-08)
    
    @Test("Blank output count for zero fee reserve")
    func blankOutputCountZero() {
        let count = calculator.calculateBlankOutputCount(feeReserve: 0)
        #expect(count == 0)
    }
    
    @Test("Blank output count for 1 sat fee reserve")
    func blankOutputCountOne() {
        // ceil(log2(1)) = 0, but minimum is 1
        let count = calculator.calculateBlankOutputCount(feeReserve: 1)
        #expect(count == 1)
    }
    
    @Test("Blank output count for 2 sat fee reserve")
    func blankOutputCountTwo() {
        // ceil(log2(2)) = 1, but we need 2 bits to represent 0-2
        // Actually log2(2) = 1, ceil(1) = 1, max(1, 1) = 1
        // But to represent 2, we need 2 bits (binary 10)
        let count = calculator.calculateBlankOutputCount(feeReserve: 2)
        #expect(count == 2)
    }
    
    @Test("Blank output count matches NUT-08 example - 1000 sat fee reserve")
    func nut08ExampleBlankOutputs() {
        // NUT-08 example: ceil(log2(1000)) = ceil(9.96) = 10
        let count = calculator.calculateBlankOutputCount(feeReserve: 1000)
        #expect(count == 10)
    }
    
    @Test("Blank output count for 100 sat fee reserve")
    func blankOutputCount100() {
        // ceil(log2(100)) = ceil(6.64) = 7
        let count = calculator.calculateBlankOutputCount(feeReserve: 100)
        #expect(count == 7)
    }
    
    @Test("Blank output count for exact power of 2 - 512")
    func blankOutputCountPowerOfTwo() {
        // log2(512) = 9 exactly, but 512 = 2^9 needs 10 bits to represent 0-512
        let count = calculator.calculateBlankOutputCount(feeReserve: 512)
        #expect(count == 10)
    }
    
    @Test("Blank output count for 255")
    func blankOutputCount255() {
        // 255 = 0xFF = 8 bits needed
        let count = calculator.calculateBlankOutputCount(feeReserve: 255)
        #expect(count == 8)
    }
    
    @Test("Blank output count for 256")
    func blankOutputCount256() {
        // 256 = 0x100 = 9 bits needed
        let count = calculator.calculateBlankOutputCount(feeReserve: 256)
        #expect(count == 9)
    }
    
    // MARK: - Change Amount Calculation Tests
    
    @Test("Change amounts for zero")
    func changeAmountsZero() {
        let amounts = calculator.calculateChangeAmounts(amount: 0)
        #expect(amounts.isEmpty)
    }
    
    @Test("Change amounts for 1")
    func changeAmountsOne() {
        let amounts = calculator.calculateChangeAmounts(amount: 1)
        #expect(amounts == [1])
    }
    
    @Test("Change amounts for power of 2 - 8")
    func changeAmountsPowerOfTwo() {
        let amounts = calculator.calculateChangeAmounts(amount: 8)
        #expect(amounts == [8])
    }
    
    @Test("Change amounts for NUT-08 example - 900")
    func changeAmountsNut08Example() {
        // NUT-08: 900 = 4 + 128 + 256 + 512
        let amounts = calculator.calculateChangeAmounts(amount: 900)
        #expect(amounts == [4, 128, 256, 512])
    }
    
    @Test("Change amounts for 7 - 1 + 2 + 4")
    func changeAmountsSeven() {
        let amounts = calculator.calculateChangeAmounts(amount: 7)
        #expect(amounts == [1, 2, 4])
    }
    
    @Test("Change amounts for 15 - all small powers")
    func changeAmountsFifteen() {
        let amounts = calculator.calculateChangeAmounts(amount: 15)
        #expect(amounts == [1, 2, 4, 8])
    }
    
    @Test("Change amounts for 100")
    func changeAmountsHundred() {
        // 100 = 64 + 32 + 4 = binary 1100100
        let amounts = calculator.calculateChangeAmounts(amount: 100)
        #expect(amounts == [4, 32, 64])
    }
    
    // MARK: - Swap Balance Validation Tests
    
    @Test("Valid swap with no fees")
    func validSwapNoFees() throws {
        let inputs = [
            ProofData(amount: 4, id: "test", secret: "a", C: "02a", witness: nil),
            ProofData(amount: 8, id: "test", secret: "b", C: "02b", witness: nil)
        ]
        let outputs = [
            BlindedMessageData(amount: 4, id: "test", B_: "02c", witness: nil),
            BlindedMessageData(amount: 8, id: "test", B_: "02d", witness: nil)
        ]
        
        try calculator.validateSwapBalance(inputs: inputs, outputs: outputs, fees: 0)
        // No exception means success
    }
    
    @Test("Valid swap with fees")
    func validSwapWithFees() throws {
        let inputs = [
            ProofData(amount: 10, id: "test", secret: "a", C: "02a", witness: nil),
            ProofData(amount: 10, id: "test", secret: "b", C: "02b", witness: nil)
        ]
        // inputs = 20, fees = 1, outputs should be 19
        let outputs = [
            BlindedMessageData(amount: 8, id: "test", B_: "02c", witness: nil),
            BlindedMessageData(amount: 8, id: "test", B_: "02d", witness: nil),
            BlindedMessageData(amount: 2, id: "test", B_: "02e", witness: nil),
            BlindedMessageData(amount: 1, id: "test", B_: "02f", witness: nil)
        ]
        
        try calculator.validateSwapBalance(inputs: inputs, outputs: outputs, fees: 1)
        // No exception means success
    }
    
    @Test("Invalid swap - outputs exceed inputs minus fees")
    func invalidSwapOutputsExceedInputs() {
        let inputs = [
            ProofData(amount: 10, id: "test", secret: "a", C: "02a", witness: nil)
        ]
        let outputs = [
            BlindedMessageData(amount: 10, id: "test", B_: "02c", witness: nil)
        ]
        
        #expect(throws: FeeCalculationError.self) {
            try calculator.validateSwapBalance(inputs: inputs, outputs: outputs, fees: 1)
        }
    }
    
    @Test("Invalid swap - outputs less than inputs minus fees")
    func invalidSwapOutputsLessThanExpected() {
        let inputs = [
            ProofData(amount: 10, id: "test", secret: "a", C: "02a", witness: nil)
        ]
        let outputs = [
            BlindedMessageData(amount: 8, id: "test", B_: "02c", witness: nil)
        ]
        
        #expect(throws: FeeCalculationError.self) {
            try calculator.validateSwapBalance(inputs: inputs, outputs: outputs, fees: 1)
        }
    }
    
    // MARK: - Melt Input Validation Tests
    
    @Test("Valid melt inputs - exact amount")
    func validMeltInputsExact() throws {
        let inputs = [
            ProofData(amount: 100, id: "test", secret: "a", C: "02a", witness: nil),
            ProofData(amount: 10, id: "test", secret: "b", C: "02b", witness: nil)
        ]
        
        // amount = 100, feeReserve = 10, total = 110
        try calculator.validateMeltInputs(inputs: inputs, amount: 100, feeReserve: 10)
    }
    
    @Test("Valid melt inputs - overpay")
    func validMeltInputsOverpay() throws {
        let inputs = [
            ProofData(amount: 100, id: "test", secret: "a", C: "02a", witness: nil),
            ProofData(amount: 20, id: "test", secret: "b", C: "02b", witness: nil)
        ]
        
        // amount = 100, feeReserve = 10, total required = 110, provided = 120
        try calculator.validateMeltInputs(inputs: inputs, amount: 100, feeReserve: 10)
    }
    
    @Test("Invalid melt inputs - insufficient")
    func invalidMeltInputsInsufficient() {
        let inputs = [
            ProofData(amount: 100, id: "test", secret: "a", C: "02a", witness: nil)
        ]
        
        // amount = 100, feeReserve = 10, total required = 110, provided = 100
        #expect(throws: FeeCalculationError.self) {
            try calculator.validateMeltInputs(inputs: inputs, amount: 100, feeReserve: 10)
        }
    }
    
    // MARK: - Mint Output Validation Tests
    
    @Test("Valid mint outputs")
    func validMintOutputs() throws {
        let outputs = [
            BlindedMessageData(amount: 64, id: "test", B_: "02a", witness: nil),
            BlindedMessageData(amount: 32, id: "test", B_: "02b", witness: nil),
            BlindedMessageData(amount: 4, id: "test", B_: "02c", witness: nil)
        ]
        
        try calculator.validateMintOutputs(outputs: outputs, expectedAmount: 100)
    }
    
    @Test("Invalid mint outputs - exceeds expected")
    func invalidMintOutputsExceeds() {
        let outputs = [
            BlindedMessageData(amount: 64, id: "test", B_: "02a", witness: nil),
            BlindedMessageData(amount: 64, id: "test", B_: "02b", witness: nil)
        ]
        
        #expect(throws: FeeCalculationError.self) {
            try calculator.validateMintOutputs(outputs: outputs, expectedAmount: 100)
        }
    }
    
    @Test("Invalid mint outputs - less than expected")
    func invalidMintOutputsLess() {
        let outputs = [
            BlindedMessageData(amount: 32, id: "test", B_: "02a", witness: nil),
            BlindedMessageData(amount: 32, id: "test", B_: "02b", witness: nil)
        ]
        
        #expect(throws: FeeCalculationError.self) {
            try calculator.validateMintOutputs(outputs: outputs, expectedAmount: 100)
        }
    }
    
    // MARK: - Fee Reserve Estimation Tests
    
    @Test("Fee reserve estimation - basic")
    func feeReserveBasic() {
        // Default: baseFee=1, feeRate=0.01 (1%)
        let reserve = calculator.estimateFeeReserve(amount: 100)
        // 1 + ceil(100 * 0.01) = 1 + 1 = 2
        #expect(reserve == 2)
    }
    
    @Test("Fee reserve estimation - larger amount")
    func feeReserveLargeAmount() {
        let reserve = calculator.estimateFeeReserve(amount: 10000)
        // 1 + ceil(10000 * 0.01) = 1 + 100 = 101
        #expect(reserve == 101)
    }
    
    @Test("Fee reserve estimation - minimum 1 sat")
    func feeReserveMinimum() {
        let reserve = calculator.estimateFeeReserve(amount: 1, baseFee: 0, feeRate: 0.001)
        // 0 + ceil(1 * 0.001) = 0 + 1 = 1 (minimum)
        #expect(reserve >= 1)
    }
    
    @Test("Fee reserve estimation - custom parameters")
    func feeReserveCustom() {
        let reserve = calculator.estimateFeeReserve(amount: 1000, baseFee: 10, feeRate: 0.005)
        // 10 + ceil(1000 * 0.005) = 10 + 5 = 15
        #expect(reserve == 15)
    }
    
    // MARK: - Overpaid Amount Calculation Tests
    
    @Test("Overpaid amount calculation - NUT-08 example")
    func overpaidAmountNut08Example() {
        // Example: inputs=101000, amount=100000, actualFeePaid=100, inputFees=0
        // overpaid = 101000 - 100000 - 100 - 0 = 900
        let overpaid = calculator.calculateOverpaidAmount(
            inputSum: 101000,
            amount: 100000,
            actualFeePaid: 100,
            inputFees: 0
        )
        #expect(overpaid == 900)
    }
    
    @Test("Overpaid amount with input fees")
    func overpaidAmountWithInputFees() {
        // inputs=1020, amount=1000, actualFee=10, inputFees=2
        // overpaid = 1020 - 1000 - 10 - 2 = 8
        let overpaid = calculator.calculateOverpaidAmount(
            inputSum: 1020,
            amount: 1000,
            actualFeePaid: 10,
            inputFees: 2
        )
        #expect(overpaid == 8)
    }
    
    @Test("Overpaid amount zero")
    func overpaidAmountZero() {
        // Exact payment
        let overpaid = calculator.calculateOverpaidAmount(
            inputSum: 110,
            amount: 100,
            actualFeePaid: 10,
            inputFees: 0
        )
        #expect(overpaid == 0)
    }
    
    @Test("Overpaid amount negative clamps to zero")
    func overpaidAmountNegativeClamped() {
        // This shouldn't happen in practice, but the function should handle it
        let overpaid = calculator.calculateOverpaidAmount(
            inputSum: 100,
            amount: 100,
            actualFeePaid: 10,
            inputFees: 0
        )
        #expect(overpaid == 0)
    }
}
