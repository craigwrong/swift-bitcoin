import Foundation
import BitcoinCrypto

enum HDExtendedKeyError: Error {
    case invalidEncoding, wrongDataLength, unknownNetwork, invalidPrivateKeyLength, invalidSecretKey, invalidPublicKeyEncoding, invalidPublicKey, zeroDepthNonZeroFingerprint, zeroDepthNonZeroIndex
}

/// A BIP32 extended key whether it be a private master key, extended private key or an extended public key.
struct HDExtendedKey {
    let network: WalletNetwork
    let isPrivate: Bool
    let key: Data
    let chaincode: Data
    let fingerprint: Int
    let depth: Int
    let keyIndex: Int

    init(network: WalletNetwork = .main, isPrivate: Bool, key: Data, chaincode: Data, fingerprint: Int, depth: Int, keyIndex: Int) throws {
        guard depth != 0 || fingerprint == 0 else {
            throw HDExtendedKeyError.zeroDepthNonZeroFingerprint
        }
        guard depth != 0 || keyIndex == 0 else {
            throw HDExtendedKeyError.zeroDepthNonZeroIndex
        }
        self.network = network
        self.isPrivate = isPrivate
        self.key = key
        self.chaincode = chaincode
        self.fingerprint = fingerprint
        self.depth = depth
        self.keyIndex = keyIndex
    }

    init(_ serialized: String) throws {
        guard let data = Base58.base58CheckDecode(serialized) else {
            throw HDExtendedKeyError.invalidEncoding
        }
        try self.init(data)
    }

    var serialized: String {
        Base58.base58CheckEncode(data)
    }
    
    /// Derives either a child private key from a parent private key, or a child public key form a parent public key.
    ///
    /// Part of  BIP32 implementation.
    ///
    /// - Parameters:
    ///   - child: The child index.
    ///   - harden: Whether to apply hardened derivation. Only applicable to private keys.
    /// - Returns: The derived child key.
    func derive(child: Int, harden: Bool = false) -> Self {
        let keyIndex = harden ? (1 << 31) + child : child
        let depth = depth + 1
        let publicKey = isPrivate ? getPublicKey(secretKey: key) : key
        let publicKeyIdentifier = hash160(publicKey)
        let fingerprint = publicKeyIdentifier.withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self)
        }

        // assert(IsValid());
        // assert(IsCompressed());
        let hmacResult: Data
        if keyIndex >> 31 == 0 {
            // Unhardened derivation
            var publicKeyData = isPrivate ? publicKey : key
            publicKeyData.appendBytes(UInt32(keyIndex).bigEndian)
            hmacResult = hmacSHA512(chaincode, data: publicKeyData)
        } else {
            // Hardened derivation
            precondition(isPrivate)
            var privateKeyData = Data([0x00])
            privateKeyData.append(key)
            privateKeyData.appendBytes(UInt32(keyIndex).bigEndian)
            hmacResult = hmacSHA512(chaincode, data: privateKeyData)
        }

        let chaincode = hmacResult[hmacResult.startIndex.advanced(by: 32)...]

        let tweak = hmacResult[..<hmacResult.startIndex.advanced(by: 32)]
        let key = if isPrivate {
            tweakSecretKey(key, tweak: tweak)
        } else {
            tweakPublicKey(key, tweak: tweak)
        }

        guard let ret = try? Self(isPrivate: isPrivate, key: key, chaincode: chaincode, fingerprint: Int(fingerprint), depth: depth, keyIndex: keyIndex) else {
            preconditionFailure()
        }
        return ret
    }

    /// Turns a private key into a public key removing its ability to produce signatures.
    var neutered: Self {
        let publicKey = getPublicKey(secretKey: key)
        guard let ret = try? Self(isPrivate: false, key: publicKey, chaincode: chaincode, fingerprint: fingerprint, depth: depth, keyIndex: keyIndex) else {
            preconditionFailure()
        }
        return ret
    }
}

extension HDExtendedKey {

    init(_ data: Data) throws {
        guard data.count == Self.size else {
            throw HDExtendedKeyError.wrongDataLength
        }

        var data = data
        let version = data.withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self)
        }.byteSwapped // Convert to little-endian

        guard let network = WalletNetwork.fromHDKeyVersion(version) else {
            throw HDExtendedKeyError.unknownNetwork
        }

        data = data.dropFirst(MemoryLayout<UInt32>.size)

        let depth = data.withUnsafeBytes {
            $0.loadUnaligned(as: UInt8.self)
        }
        data = data.dropFirst(MemoryLayout<UInt8>.size)

        let fingerprint = data.withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self)
        }
        data = data.dropFirst(MemoryLayout<UInt32>.size)

        let keyIndex = data.withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self)
        }.byteSwapped // Convert to little-endian
        data = data.dropFirst(MemoryLayout<UInt32>.size)

        let chaincode = data[..<data.startIndex.advanced(by: 32)]
        data = data.dropFirst(32)

        let isPrivate = version == network.hdKeyVersionPrivate

        let key: Data
        if isPrivate {
            guard data[data.startIndex] == 0 else {
                throw HDExtendedKeyError.invalidPrivateKeyLength
            }
            key = data[data.startIndex.advanced(by: 1)..<data.startIndex.advanced(by: 33)]
            guard checkSecretKey(key) else {
                throw HDExtendedKeyError.invalidSecretKey
            }
        } else {
            key = data[..<data.startIndex.advanced(by: 33)]
            guard checkPublicKeyEncoding(key) else {
                throw HDExtendedKeyError.invalidPublicKeyEncoding
            }
            guard checkPublicKey(key) else {
                throw HDExtendedKeyError.invalidPublicKey
            }
        }
        data = data.dropFirst(33)
        try self.init(network: network, isPrivate: isPrivate, key: key, chaincode: chaincode, fingerprint: Int(fingerprint), depth: Int(depth), keyIndex: Int(keyIndex))
    }

    var versionData: Data {
        var ret = Data(count: Self.versionSize)
        let version = if isPrivate {
            network.hdKeyVersionPrivate
        } else {
            network.hdKeyVersionPublic
        }
        ret.addBytes(UInt32(version).bigEndian)
        return ret
    }

    var data: Data {
        var ret = Data(count: Self.size)
        var offset = ret.addData(versionData)
        offset = ret.addBytes(UInt8(depth), at: offset)
        offset = ret.addBytes(UInt32(fingerprint), at: offset)
        offset = ret.addBytes(UInt32(keyIndex).bigEndian, at: offset)
        offset = ret.addData(chaincode, at: offset)
        if isPrivate {
            offset = ret.addData([0], at: offset)
        }
        ret.addData(key, at: offset)
        return ret
    }

    static let versionSize = MemoryLayout<UInt32>.size
    static let size = 78
}
