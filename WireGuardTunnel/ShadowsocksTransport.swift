// ShadowsocksTransport.swift
// WireGuardTunnel
//
// Pure-Swift SS-2022 AEAD client transport.
// Cipher: 2022-blake3-aes-256-gcm
// Wire: EIH(16) + RequestSalt(32) + AEAD(FixedHeader, aad=salt) + AEAD chunks
// Subkey: HKDF-SHA1(ikm=userPSK, salt=requestSalt, info="ss-subkey")
// EIH key: BLAKE3(serverPSK || requestSalt)[0..16]  (inline BLAKE3 — no external dep)
// No Go toolchain required.

import Foundation
@preconcurrency import Network
import CryptoKit
import CommonCrypto
import NetworkExtension

// MARK: - Configuration

struct SSTunnelConfig {
    let server: String          // hostname, e.g. "vpn-iad-01.vpn.katafract.com"
    let port: UInt16            // TLS port, e.g. 8443
    let password: String        // "SERVER_PSK_b64:USER_PSK_b64"
    let serverNodeIP: String    // WG server public IP, e.g. "87.99.128.159"
}

// MARK: - Errors

enum ShadowsocksError: LocalizedError {
    case invalidPassword
    case invalidBase64
    case connectionFailed(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidState(String)
    case ioError(String)

    var errorDescription: String? {
        switch self {
        case .invalidPassword:
            return "Invalid Shadowsocks password format (expected SERVER_PSK:USER_PSK)"
        case .invalidBase64:
            return "Invalid base64 encoding in Shadowsocks password"
        case .connectionFailed(let msg):
            return "Shadowsocks connection failed: \(msg)"
        case .encryptionFailed(let msg):
            return "Shadowsocks encryption failed: \(msg)"
        case .decryptionFailed(let msg):
            return "Shadowsocks decryption failed: \(msg)"
        case .invalidState(let msg):
            return "Shadowsocks invalid state: \(msg)"
        case .ioError(let msg):
            return "Shadowsocks I/O error: \(msg)"
        }
    }
}

// MARK: - Shadowsocks Transport

actor ShadowsocksTransport {
    private var connection: NWConnection?
    private var running = false
    private var sendNonce: UInt64 = 1   // nonce 0 consumed by fixed header
    private var recvNonce: UInt64 = 0   // server responses start at 0

    private var subkey: Data?
    private var serverPSK: Data?
    private var userPSK: Data?

    nonisolated private let log = { (msg: String) in
        NSLog("[ShadowsocksTransport] %@", msg)
    }

    // MARK: - Lifecycle

    func start(config: SSTunnelConfig, packetFlow: NEPacketTunnelFlow) async throws {
        log("Starting to \(config.server):\(config.port)")

        // Parse "SERVER_PSK_b64:USER_PSK_b64"
        let (serverPSKData, userPSKData) = try parsePassword(config.password)
        self.serverPSK = serverPSKData
        self.userPSK = userPSKData

        // 32-byte random request salt
        var requestSalt = Data(count: 32)
        let saltResult = requestSalt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard saltResult == errSecSuccess else {
            throw ShadowsocksError.encryptionFailed("SecRandomCopyBytes failed")
        }

        // Derive session subkey: HKDF-SHA1(ikm=userPSK, salt=requestSalt)
        let derivedSubkey = try deriveSubkey(ikm: userPSKData, salt: requestSalt)
        self.subkey = derivedSubkey

        // Build 16-byte EIH block for multi-user ssservice
        let eihBlock = try buildEIH(
            serverPSK: serverPSKData,
            userPSK: userPSKData,
            requestSalt: requestSalt
        )

        // Build and encrypt the fixed header (nonce=0, aad=requestSalt)
        let fixedHeaderPlaintext = try buildFixedHeader(
            serverNodeIP: config.serverNodeIP,
            timestamp: UInt64(Date().timeIntervalSince1970)
        )
        let encryptedHeader = try encryptAEAD(
            key: derivedSubkey,
            nonce: makeNonce(counter: 0),
            plaintext: fixedHeaderPlaintext,
            aad: requestSalt
        )
        self.sendNonce = 1

        // Open TLS connection (v2ray-plugin terminates TLS on the server side)
        let host = NWEndpoint.Host(config.server)
        guard let port = NWEndpoint.Port(rawValue: config.port) else {
            throw ShadowsocksError.connectionFailed("Invalid port: \(config.port)")
        }
        let tlsParams = NWParameters(tls: NWProtocolTLS.Options())
        tlsParams.preferNoProxy = true
        let conn = NWConnection(host: host, port: port, using: tlsParams)
        self.connection = conn

        try await waitForConnectionReady(connection: conn)
        log("TLS connected")

        // Wire prefix: EIH(16) + salt(32) + AEAD(fixedHeader)
        let wirePrefix = eihBlock + requestSalt + encryptedHeader
        try await sendData(wirePrefix, connection: conn)
        log("Sent wire prefix (\(wirePrefix.count) bytes)")

        self.running = true

        // Spawn read + write loops
        Task { await self.readLoop(connection: conn, packetFlow: packetFlow) }
        Task { await self.writeLoop(connection: conn, packetFlow: packetFlow) }
    }

    func stop() async {
        log("Stopping")
        running = false
        connection?.cancel()
        connection = nil
    }

    // MARK: - Read Loop (Server → WireGuard)

    private func readLoop(connection: NWConnection, packetFlow: NEPacketTunnelFlow) async {
        while running {
            do {
                guard let subkey = self.subkey else {
                    throw ShadowsocksError.invalidState("Subkey not set")
                }

                // Encrypted length: 2-byte plaintext + 16-byte GCM tag = 18 bytes on wire
                let encLen = try await receiveExactly(18, from: connection)
                let lenData = try decryptAEAD(
                    key: subkey,
                    nonce: makeNonce(counter: recvNonce),
                    ciphertext: encLen,
                    aad: Data()
                )
                guard lenData.count == 2 else {
                    throw ShadowsocksError.decryptionFailed("Length block wrong size: \(lenData.count)")
                }
                let payloadLen = Int(lenData.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })
                recvNonce += 1

                // Encrypted payload: N bytes + 16-byte GCM tag
                let encPayload = try await receiveExactly(payloadLen + 16, from: connection)
                let payload = try decryptAEAD(
                    key: subkey,
                    nonce: makeNonce(counter: recvNonce),
                    ciphertext: encPayload,
                    aad: Data()
                )
                recvNonce += 1

                packetFlow.writePackets([payload], withProtocols: [AF_INET as NSNumber])
                log("→ WG \(payload.count) bytes")

            } catch {
                log("Read loop error: \(error.localizedDescription)")
                running = false
            }
        }
    }

    // MARK: - Write Loop (WireGuard → Server)

    private func writeLoop(connection: NWConnection, packetFlow: NEPacketTunnelFlow) async {
        while running {
            do {
                guard let subkey = self.subkey else {
                    throw ShadowsocksError.invalidState("Subkey not set")
                }

                // readPacketObjects is callback-based; bridge to async
                let packets: [NEPacket] = await withCheckedContinuation { continuation in
                    packetFlow.readPacketObjects { pkts in
                        continuation.resume(returning: pkts ?? [])
                    }
                }

                guard !packets.isEmpty else {
                    try await Task.sleep(nanoseconds: 10_000_000)  // 10 ms
                    continue
                }

                for packet in packets {
                    let payload = packet.data

                    // Encrypt length (2 bytes big-endian uint16)
                    var lenBE = UInt16(payload.count).bigEndian
                    let lenPlaintext = Data(bytes: &lenBE, count: 2)
                    let encLen = try encryptAEAD(
                        key: subkey,
                        nonce: makeNonce(counter: sendNonce),
                        plaintext: lenPlaintext,
                        aad: Data()
                    )
                    sendNonce += 1

                    // Encrypt payload
                    let encPayload = try encryptAEAD(
                        key: subkey,
                        nonce: makeNonce(counter: sendNonce),
                        plaintext: payload,
                        aad: Data()
                    )
                    sendNonce += 1

                    let chunk = encLen + encPayload
                    try await sendData(chunk, connection: connection)
                    log("WG → \(payload.count) bytes (\(chunk.count) on wire)")
                }

            } catch {
                log("Write loop error: \(error.localizedDescription)")
                running = false
            }
        }
    }

    // MARK: - Cryptography

    private func parsePassword(_ password: String) throws -> (serverPSK: Data, userPSK: Data) {
        let parts = password.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw ShadowsocksError.invalidPassword }

        guard let serverPSKData = Data(base64Encoded: String(parts[0])),
              serverPSKData.count == 32 else {
            throw ShadowsocksError.invalidBase64
        }
        guard let userPSKData = Data(base64Encoded: String(parts[1])),
              userPSKData.count == 32 else {
            throw ShadowsocksError.invalidBase64
        }
        return (serverPSKData, userPSKData)
    }

    /// HKDF-SHA1(ikm: userPSK, salt: requestSalt, info: "ss-subkey", outputByteCount: 32)
    private func deriveSubkey(ikm: Data, salt: Data) throws -> Data {
        let info = Data("ss-subkey".utf8)
        let derivedKey = HKDF<Insecure.SHA1>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: salt,
            info: info,
            outputByteCount: 32
        )
        return derivedKey.withUnsafeBytes { Data($0) }
    }

    /// EIH = AES-128-ECB(key: BLAKE3(serverPSK||requestSalt)[0..16], plaintext: userPSK[0..16])
    private func buildEIH(serverPSK: Data, userPSK: Data, requestSalt: Data) throws -> Data {
        var hashInput = Data()
        hashInput.append(serverPSK)
        hashInput.append(requestSalt)
        let hash = blake3Hash(hashInput)          // real BLAKE3 — see bottom of file
        let eihKey = hash.prefix(16)
        let plaintext = userPSK.prefix(16)
        return try aesECBEncrypt(key: Data(eihKey), plaintext: Data(plaintext))
    }

    /// SS-2022 TCP fixed header: type(1) + timestamp(8) + addr_type(1) + ipv4(4) + port(2) + padding_len(2)
    private func buildFixedHeader(serverNodeIP: String, timestamp: UInt64) throws -> Data {
        var header = Data()

        header.append(0x00)  // type: TCP request

        var ts = timestamp.bigEndian
        header.append(Data(bytes: &ts, count: 8))

        header.append(0x01)  // addr_type: IPv4

        let octets = serverNodeIP.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else {
            throw ShadowsocksError.encryptionFailed("Invalid IPv4: \(serverNodeIP)")
        }
        header.append(contentsOf: octets)

        var wgPort = UInt16(51820).bigEndian
        header.append(Data(bytes: &wgPort, count: 2))

        header.append(contentsOf: [0x00, 0x00])  // initial payload length = 0

        return header
    }

    private func encryptAEAD(key: Data, nonce: Data, plaintext: Data, aad: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let nonceObj = try AES.GCM.Nonce(data: nonce)
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey, nonce: nonceObj, authenticating: aad)
        return Data(sealedBox.ciphertext) + Data(sealedBox.tag)
    }

    private func decryptAEAD(key: Data, nonce: Data, ciphertext: Data, aad: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let nonceObj = try AES.GCM.Nonce(data: nonce)
        guard ciphertext.count >= 16 else {
            throw ShadowsocksError.decryptionFailed("Ciphertext too short: \(ciphertext.count)")
        }
        let ct = ciphertext.dropLast(16)
        let tag = ciphertext.suffix(16)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonceObj, ciphertext: ct, tag: tag)
        return try AES.GCM.open(sealedBox, using: symmetricKey, authenticating: aad)
    }

    private func aesECBEncrypt(key: Data, plaintext: Data) throws -> Data {
        var ciphertext = [UInt8](repeating: 0, count: plaintext.count)
        var numBytesEncrypted = 0
        let status: CCCryptorStatus = key.withUnsafeBytes { keyBytes in
            plaintext.withUnsafeBytes { ptBytes in
                CCCrypt(
                    CCOperation(kCCEncrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionECBMode),
                    keyBytes.baseAddress, key.count,
                    nil,
                    ptBytes.baseAddress, plaintext.count,
                    &ciphertext, ciphertext.count,
                    &numBytesEncrypted
                )
            }
        }
        guard status == kCCSuccess else {
            throw ShadowsocksError.encryptionFailed("AES-ECB failed: \(status)")
        }
        return Data(ciphertext.prefix(numBytesEncrypted))
    }

    // MARK: - Nonce

    /// SS-2022 nonce: 4 zero bytes + 8-byte counter big-endian = 12 bytes
    private func makeNonce(counter: UInt64) -> Data {
        var nonce = Data(count: 12)
        nonce.withUnsafeMutableBytes { buf in
            var c = counter.bigEndian
            memcpy(buf.baseAddress! + 4, &c, 8)
        }
        return nonce
    }

    // MARK: - Network I/O

    private func waitForConnectionReady(connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume()
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: ShadowsocksError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    resumed = true
                    continuation.resume(throwing: ShadowsocksError.connectionFailed("Cancelled"))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                if !resumed {
                    resumed = true
                    continuation.resume(throwing: ShadowsocksError.connectionFailed("Timeout"))
                }
            }
        }
    }

    private func sendData(_ data: Data, connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: ShadowsocksError.ioError(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receiveExactly(_ count: Int, from connection: NWConnection) async throws -> Data {
        var buffer = Data()
        while buffer.count < count {
            let remaining = count - buffer.count
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, isComplete, error in
                    if let error = error {
                        continuation.resume(throwing: ShadowsocksError.ioError(error.localizedDescription))
                    } else if let data = data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(throwing: ShadowsocksError.ioError("Connection closed"))
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
            }
            if chunk.isEmpty {
                try await Task.sleep(nanoseconds: 1_000_000)
            } else {
                buffer.append(chunk)
            }
        }
        return buffer
    }
}

// MARK: - Inline BLAKE3
//
// Minimal BLAKE3 hash (output: 32 bytes) for SS-2022 EIH key derivation.
// Implements the BLAKE3 spec (https://github.com/BLAKE3-team/BLAKE3-specs)
// for inputs ≤ 64 bytes (single chunk, ROOT flag set).
// Only the hash function is implemented — no XOF, no keyed mode.

private let blake3IV: [UInt32] = [
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
]

private let blake3MsgPermutation: [Int] = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]

private let blake3CHUNK_START:  UInt32 = 1 << 0
private let blake3CHUNK_END:    UInt32 = 1 << 1
private let blake3ROOT:         UInt32 = 1 << 3

private func blake3G(
    _ state: inout [UInt32], a: Int, b: Int, c: Int, d: Int,
    mx: UInt32, my: UInt32
) {
    state[a] = state[a] &+ state[b] &+ mx
    state[d] = (state[d] ^ state[a]).rotateRight(16)
    state[c] = state[c] &+ state[d]
    state[b] = (state[b] ^ state[c]).rotateRight(12)
    state[a] = state[a] &+ state[b] &+ my
    state[d] = (state[d] ^ state[a]).rotateRight(8)
    state[c] = state[c] &+ state[d]
    state[b] = (state[b] ^ state[c]).rotateRight(7)
}

private func blake3Round(_ state: inout [UInt32], m: [UInt32]) {
    // column step
    blake3G(&state, a: 0, b: 4, c: 8,  d: 12, mx: m[0],  my: m[1])
    blake3G(&state, a: 1, b: 5, c: 9,  d: 13, mx: m[2],  my: m[3])
    blake3G(&state, a: 2, b: 6, c: 10, d: 14, mx: m[4],  my: m[5])
    blake3G(&state, a: 3, b: 7, c: 11, d: 15, mx: m[6],  my: m[7])
    // diagonal step
    blake3G(&state, a: 0, b: 5, c: 10, d: 15, mx: m[8],  my: m[9])
    blake3G(&state, a: 1, b: 6, c: 11, d: 12, mx: m[10], my: m[11])
    blake3G(&state, a: 2, b: 7, c: 8,  d: 13, mx: m[12], my: m[13])
    blake3G(&state, a: 3, b: 4, c: 9,  d: 14, mx: m[14], my: m[15])
}

private func blake3Compress(
    cv: [UInt32], block: [UInt32], blockLen: UInt32,
    counter: UInt64, flags: UInt32
) -> [UInt32] {
    var state: [UInt32] = [
        cv[0], cv[1], cv[2], cv[3],
        cv[4], cv[5], cv[6], cv[7],
        blake3IV[0], blake3IV[1], blake3IV[2], blake3IV[3],
        UInt32(counter & 0xFFFFFFFF), UInt32(counter >> 32),
        blockLen, flags
    ]

    var m = block
    for _ in 0..<7 {
        blake3Round(&state, m: m)
        var permuted = [UInt32](repeating: 0, count: 16)
        for i in 0..<16 { permuted[i] = m[blake3MsgPermutation[i]] }
        m = permuted
    }

    for i in 0..<8 {
        state[i]     ^= state[i + 8]
        state[i + 8] ^= cv[i]
    }
    return state
}

/// Compute BLAKE3(input) → 32 bytes. Handles inputs up to 64 bytes.
func blake3Hash(_ input: Data) -> Data {
    // Pad input to 64 bytes (one BLAKE3 block)
    var padded = [UInt8](input) + [UInt8](repeating: 0, count: max(0, 64 - input.count))
    padded = Array(padded.prefix(64))

    // Read 16 little-endian uint32 words from the 64-byte block
    var block = [UInt32](repeating: 0, count: 16)
    for i in 0..<16 {
        let off = i * 4
        block[i] = UInt32(padded[off])
            | (UInt32(padded[off + 1]) << 8)
            | (UInt32(padded[off + 2]) << 16)
            | (UInt32(padded[off + 3]) << 24)
    }

    // Single chunk: CHUNK_START | CHUNK_END | ROOT
    let flags: UInt32 = blake3CHUNK_START | blake3CHUNK_END | blake3ROOT
    let outputState = blake3Compress(
        cv: blake3IV,
        block: block,
        blockLen: UInt32(min(input.count, 64)),
        counter: 0,
        flags: flags
    )

    // First 8 words of output state → 32-byte hash (little-endian)
    var out = Data(count: 32)
    out.withUnsafeMutableBytes { buf in
        for i in 0..<8 {
            let v = outputState[i]
            buf[i * 4 + 0] = UInt8(v & 0xFF)
            buf[i * 4 + 1] = UInt8((v >> 8) & 0xFF)
            buf[i * 4 + 2] = UInt8((v >> 16) & 0xFF)
            buf[i * 4 + 3] = UInt8((v >> 24) & 0xFF)
        }
    }
    return out
}

private extension UInt32 {
    func rotateRight(_ n: Int) -> UInt32 {
        return (self >> n) | (self << (32 - n))
    }
}
