// ShadowsocksAEADTests.swift
// WraithVPNTests
//
// Unit tests for SS-2022 crypto primitives used in ShadowsocksTransport.
// ShadowsocksTransport.swift compiles into WireGuardTunnel (a separate app extension
// target), so these tests duplicate the relevant crypto inline.
// All tests are simulator-runnable with no network required.

import XCTest
import CryptoKit
import CommonCrypto

final class ShadowsocksAEADTests: XCTestCase {

    // MARK: - AES-128-ECB (used in EIH block construction)

    func testAES128ECBKnownVector() throws {
        // NIST FIPS 197 AES-128 ECB test vector
        // Key:       2b7e151628aed2a6abf7158809cf4f3c
        // Plaintext: 6bc1bee22e409f96e93d7e117393172a
        // Ciphertext:3ad77bb40d7a3660a89ecaf32466ef97
        let key = Data([
            0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6,
            0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c
        ])
        let plaintext = Data([
            0x6b, 0xc1, 0xbe, 0xe2, 0x2e, 0x40, 0x9f, 0x96,
            0xe9, 0x3d, 0x7e, 0x11, 0x73, 0x93, 0x17, 0x2a
        ])
        let expectedCiphertext = Data([
            0x3a, 0xd7, 0x7b, 0xb4, 0x0d, 0x7a, 0x36, 0x60,
            0xa8, 0x9e, 0xca, 0xf3, 0x24, 0x66, 0xef, 0x97
        ])

        var ciphertext = [UInt8](repeating: 0, count: plaintext.count)
        var ciphertextLen = 0

        let status: CCCryptorStatus = plaintext.withUnsafeBytes { ptBytes in
            key.withUnsafeBytes { keyBytes in
                CCCrypt(
                    CCOperation(kCCEncrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionECBMode),
                    keyBytes.baseAddress, key.count,
                    nil,
                    ptBytes.baseAddress, plaintext.count,
                    &ciphertext, ciphertext.count,
                    &ciphertextLen
                )
            }
        }

        XCTAssertEqual(status, kCCSuccess, "AES-128-ECB must succeed")
        XCTAssertEqual(ciphertextLen, 16, "Ciphertext must be 16 bytes")
        XCTAssertEqual(Data(ciphertext.prefix(ciphertextLen)), expectedCiphertext,
                       "AES-128-ECB output must match NIST vector")
    }

    // MARK: - HKDF-SHA1 subkey derivation

    func testHKDFSHA1Determinism() throws {
        // Verify that HKDF<Insecure.SHA1> is deterministic for SS-2022 subkey derivation.
        // ikm = 32-byte userPSK, salt = 32-byte requestSalt, info = "ss-subkey"
        let ikm = Data(repeating: 0xAB, count: 32)
        let salt = Data(repeating: 0xCD, count: 32)
        let info = Data("ss-subkey".utf8)

        func derive() -> Data {
            let key = HKDF<Insecure.SHA1>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: ikm),
                salt: salt,
                info: info,
                outputByteCount: 32
            )
            return key.withUnsafeBytes { Data($0) }
        }

        let key1 = derive()
        let key2 = derive()

        XCTAssertEqual(key1.count, 32, "Derived subkey must be 32 bytes")
        XCTAssertEqual(key1, key2, "HKDF must be deterministic")
        XCTAssertNotEqual(key1, ikm, "Derived key must differ from IKM")
    }

    // MARK: - AES-256-GCM AEAD round-trip

    func testAES256GCMRoundTrip() throws {
        // Verify AES-256-GCM seal/open round-trip (used for all SS-2022 chunk encryption)
        let key = SymmetricKey(size: .bits256)

        // 12-byte SS-2022 nonce: 4 zero bytes + 8-byte counter big-endian
        var nonceBytes = Data(count: 12)
        nonceBytes.withUnsafeMutableBytes { buf in
            var counter: UInt64 = 1
            counter = counter.bigEndian
            memcpy(buf.baseAddress! + 4, &counter, 8)
        }
        let nonce = try AES.GCM.Nonce(data: nonceBytes)

        let plaintext = Data("test WireGuard packet payload".utf8)
        let aad = Data("request-salt-aad".utf8)

        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
        let ciphertextPlusTag = Data(sealed.ciphertext) + Data(sealed.tag)

        XCTAssertEqual(ciphertextPlusTag.count, plaintext.count + 16,
                       "Wire ciphertext = plaintext + 16-byte GCM tag")

        // Reconstruct SealedBox from ciphertext+tag (as done in decryptAEAD)
        let ct = ciphertextPlusTag.dropLast(16)
        let tag = ciphertextPlusTag.suffix(16)
        let reconstructed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
        let decrypted = try AES.GCM.open(reconstructed, using: key, authenticating: aad)

        XCTAssertEqual(decrypted, plaintext, "Decrypted output must match original plaintext")
    }
}
