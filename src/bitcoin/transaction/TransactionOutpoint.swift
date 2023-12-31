import Foundation

/// A reference to a particular ``Output`` of a particular ``Transaction``.
public struct TransactionOutpoint: Equatable, Hashable {

    init(transaction: Data, output: Int) {
        precondition(transaction.count == BitcoinTransaction.identifierSize)
        self.transactionIdentifier = transaction
        self.outputIndex = output
    }

    init?(_ data: Data) {
        guard data.count >= Self.size else {
            return nil
        }
        var offset = data.startIndex
        let transaction = Data(data[offset ..< offset + BitcoinTransaction.identifierSize].reversed())
        offset += BitcoinTransaction.identifierSize
        let outputData = data[offset ..< offset + MemoryLayout<UInt32>.size]
        let output = Int(outputData.withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self)
        })
        self.init(transaction: transaction, output: output)
    }

    // The identifier for the transaction containing the referenced output.
    public let transactionIdentifier: Data

    /// The index of an output in the referenced transaction.
    public let outputIndex: Int

    var data: Data {
        var ret = Data()
        ret += transactionIdentifier.reversed()
        ret += withUnsafeBytes(of: UInt32(outputIndex)) { Data($0) }
        return ret
    }

    public static let coinbase = Self(
        transaction: .init(count: BitcoinTransaction.identifierSize),
        output: 0xffffffff
    )

    static let size = BitcoinTransaction.identifierSize + MemoryLayout<UInt32>.size
}
