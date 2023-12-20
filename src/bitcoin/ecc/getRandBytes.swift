import Foundation


/// Generates the specified number of random bytes.
///
/// Because it ultimately relies on `Swift/SystemRandomNumberGenerator` which in turn uses a cryptographically secure algorithm whenever possible, this function too can be considered safe on Apple Platforms, Linux, BSD and Windows.
///
/// - Parameter byteCount: The number of random bytes to generate.
/// - Returns: The generated random sequence of bytes.
///
public func getRandBytes(_ byteCount: Int) -> Data {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    for i in bytes.indices {
        bytes[i] = .random(in: UInt8.min...UInt8.max)
    }
    return Data(bytes)
}

func getRandBytesExtern(_ bytesOut: UnsafeMutablePointer<UInt8>!, _ byteCount: Int) {
    let byteCountInt = Int(byteCount)
    let resultData = getRandBytes(byteCountInt)
    resultData.copyBytes(to: bytesOut, from: 0 ..< byteCountInt)
}
