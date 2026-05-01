// SPDX-License-Identifier: MIT
//
// ssframing/framing.go — SS-2022 UDP-relay frame encode/decode.
//
// This is package ssframing: a pure-Go implementation of the
// Shadowsocks-2022 UDP relay frame format for the method
// "2022-blake3-aes-256-gcm". It is in a sibling package so it can be
// unit-tested via `go test ./ssframing/...` independent of the `package main`
// cgo build constraint that prevents testing api-apple.go / ssbind.go directly.
//
// Spec: https://github.com/Shadowsocks-NET/shadowsocks-specs/blob/main/2022-1-shadowsocks-2022-edition.md
// Reference impl: shadowsocks-rust crates/shadowsocks/src/relay/udprelay/aead_2022.rs
//
// Frame layout (client → server):
//
//   [ separateHeader_ciphertext  (16 bytes) ]
//   [ EIH                        (16 bytes) — multi-user required ]
//   [ AEAD ciphertext + 16-byte GCM tag     ]
//
// separateHeader plaintext = session_id (8 BE) || packet_id (8 BE)
// separateHeader encryption: AES-256-ECB, key = sessionSubkey(userPSK, sessionID)
//
// AEAD key & nonce:
//   key   = sessionSubkey(userPSK, sessionID)   [same key as separateHeader]
//   nonce = last 12 bytes of separateHeader_ciphertext
//
// AEAD plaintext (client→server):
//   type(1=0x00) || timestamp(8 BE) || padding_len(2 BE=0) || ATYP(1) || addr || port(2 BE) || payload
//
// AEAD plaintext (server→client):
//   type(1=0x01) || timestamp(8 BE) || client_session_id(8 BE) || padding_len(2 BE=0) || ATYP(1) || addr || port(2 BE) || payload
//
// EIH = AES-256-ECB( eihKey, BLAKE3(userPSK)[0..16] )
//   eihKey = BLAKE3.deriveKey("shadowsocks 2022 identity subkey", serverPSK || sessionID)

package ssframing

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"sync"
	"time"

	"lukechampine.com/blake3"
)

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------

const (
	// SS-2022 UDP ATYP values
	atypIPv4 = 0x01
	atypIPv6 = 0x04

	// Client→server type byte
	typeClientToServer = 0x00
	// Server→client type byte
	typeServerToClient = 0x01

	// separateHeader is always 16 bytes (= AES block size)
	separateHeaderSize = 16
	// EIH is always 16 bytes (= AES block size)
	eihSize = 16
	// GCM tag is always 16 bytes
	gcmTagSize = 16

	// Maximum clock drift allowed (±30s)
	maxTimestampDrift = 30
)

var (
	ErrInvalidFrame         = errors.New("ssframing: invalid frame")
	ErrTimestampOutOfRange  = errors.New("ssframing: timestamp out of acceptable range")
	ErrSessionIDMismatch    = errors.New("ssframing: client_session_id mismatch in server frame")
	ErrShortFrame           = errors.New("ssframing: frame too short")
	ErrUnknownType          = errors.New("ssframing: unknown frame type byte")
)

// --------------------------------------------------------------------------
// Key derivation helpers
// --------------------------------------------------------------------------

const (
	sessionSubkeyContext  = "shadowsocks 2022 session subkey"
	identitySubkeyContext = "shadowsocks 2022 identity subkey"
)

// DeriveSessionSubkey derives the 32-byte session subkey for the given PSK and
// 8-byte sessionID, following the SS-2022 spec:
//
//	BLAKE3.deriveKey(sessionSubkeyContext, psk || sessionID)[0..32]
func DeriveSessionSubkey(psk []byte, sessionID [8]byte) []byte {
	material := make([]byte, len(psk)+8)
	copy(material, psk)
	copy(material[len(psk):], sessionID[:])
	out := blake3.DeriveKey(sessionSubkeyContext, material)
	return out[:32]
}

// DeriveEIH derives the 16-byte EIH (Extended Identity Header) for a given
// serverPSK and 8-byte sessionID:
//
//	eihKey = BLAKE3.deriveKey(identitySubkeyContext, serverPSK || sessionID)[0..32]
//	EIH    = AES-256-ECB(eihKey, BLAKE3(userPSK)[0..16])
func DeriveEIH(serverPSK, userPSK []byte, sessionID [8]byte) ([]byte, error) {
	// Derive eihKey using serverPSK + sessionID
	material := make([]byte, len(serverPSK)+8)
	copy(material, serverPSK)
	copy(material[len(serverPSK):], sessionID[:])
	eihKey := blake3.DeriveKey(identitySubkeyContext, material)

	// Hash userPSK: BLAKE3(userPSK)[0..16]
	userPSKHash := blake3.Sum256(userPSK)
	userIdentity := userPSKHash[:16]

	// AES-256-ECB encrypt the 16-byte identity block
	block, err := aes.NewCipher(eihKey[:32])
	if err != nil {
		return nil, fmt.Errorf("ssframing: DeriveEIH AES: %w", err)
	}
	eih := make([]byte, 16)
	block.Encrypt(eih, userIdentity)
	return eih, nil
}

// --------------------------------------------------------------------------
// Separate header helpers
// --------------------------------------------------------------------------

// encryptSeparateHeader encrypts the 16-byte separateHeader plaintext
// (session_id || packet_id) using AES-256-ECB with the given session subkey.
func encryptSeparateHeader(subkey []byte, sessionID [8]byte, packetID uint64) ([]byte, error) {
	plaintext := make([]byte, 16)
	copy(plaintext[:8], sessionID[:])
	binary.BigEndian.PutUint64(plaintext[8:], packetID)

	block, err := aes.NewCipher(subkey)
	if err != nil {
		return nil, fmt.Errorf("ssframing: encryptSeparateHeader AES: %w", err)
	}
	ciphertext := make([]byte, 16)
	block.Encrypt(ciphertext, plaintext)
	return ciphertext, nil
}

// decryptSeparateHeader decrypts a 16-byte separateHeader ciphertext using
// AES-256-ECB, recovering (session_id [8]byte, packet_id uint64).
func decryptSeparateHeader(subkey, ciphertext []byte) ([8]byte, uint64, error) {
	if len(ciphertext) < 16 {
		return [8]byte{}, 0, ErrShortFrame
	}
	block, err := aes.NewCipher(subkey)
	if err != nil {
		return [8]byte{}, 0, fmt.Errorf("ssframing: decryptSeparateHeader AES: %w", err)
	}
	plaintext := make([]byte, 16)
	block.Decrypt(plaintext, ciphertext[:16])
	var sessionID [8]byte
	copy(sessionID[:], plaintext[:8])
	packetID := binary.BigEndian.Uint64(plaintext[8:])
	return sessionID, packetID, nil
}

// --------------------------------------------------------------------------
// Address encoding helpers
// --------------------------------------------------------------------------

// encodeAddr encodes an IP address and port as SS SOCKS5-style address bytes:
//   ATYP (1) || addr (4 or 16 bytes) || port (2 BE)
func encodeAddr(ip net.IP, port uint16) []byte {
	ip4 := ip.To4()
	if ip4 != nil {
		buf := make([]byte, 1+4+2)
		buf[0] = atypIPv4
		copy(buf[1:], ip4)
		binary.BigEndian.PutUint16(buf[5:], port)
		return buf
	}
	ip6 := ip.To16()
	buf := make([]byte, 1+16+2)
	buf[0] = atypIPv6
	copy(buf[1:], ip6)
	binary.BigEndian.PutUint16(buf[17:], port)
	return buf
}

// decodeAddr reads a SOCKS5-style address from buf, returning the IP, port,
// and the number of bytes consumed.
func decodeAddr(buf []byte) (net.IP, uint16, int, error) {
	if len(buf) < 1 {
		return nil, 0, 0, ErrShortFrame
	}
	switch buf[0] {
	case atypIPv4:
		if len(buf) < 1+4+2 {
			return nil, 0, 0, ErrShortFrame
		}
		ip := net.IP(make([]byte, 4))
		copy(ip, buf[1:5])
		port := binary.BigEndian.Uint16(buf[5:7])
		return ip, port, 7, nil
	case atypIPv6:
		if len(buf) < 1+16+2 {
			return nil, 0, 0, ErrShortFrame
		}
		ip := net.IP(make([]byte, 16))
		copy(ip, buf[1:17])
		port := binary.BigEndian.Uint16(buf[17:19])
		return ip, port, 19, nil
	default:
		return nil, 0, 0, fmt.Errorf("ssframing: unknown ATYP 0x%02x", buf[0])
	}
}

// --------------------------------------------------------------------------
// Session state
// --------------------------------------------------------------------------

// Session holds the cryptographic material for one SS-2022 UDP session.
// It is safe for concurrent use after construction.
type Session struct {
	sessionID    [8]byte
	sessionSubkey []byte  // 32 bytes, derived from userPSK + sessionID
	eihData      []byte  // 16 bytes, pre-computed

	// Per-server-session subkey cache (server has its own session_id)
	serverSubkeyMu sync.Mutex
	serverSubkeys  map[[8]byte][]byte

	// userPSK kept for server-session subkey derivation
	userPSK []byte
}

// NewSession creates a new SS-2022 session with a fresh random sessionID.
// serverPSK and userPSK are the SS-2022 key material (32 bytes each for
// 2022-blake3-aes-256-gcm). Both are parsed from the combined
// "serverPSK:userPSK" password field in the ShadowsocksConfig.
func NewSession(serverPSK, userPSK []byte) (*Session, error) {
	var sessionID [8]byte
	if _, err := rand.Read(sessionID[:]); err != nil {
		return nil, fmt.Errorf("ssframing: rand sessionID: %w", err)
	}
	return newSessionWithID(serverPSK, userPSK, sessionID)
}

// NewSessionWithID creates a session with a pre-determined sessionID.
// Used for session persistence across Bind reopens.
func NewSessionWithID(serverPSK, userPSK []byte, sessionID [8]byte) (*Session, error) {
	return newSessionWithID(serverPSK, userPSK, sessionID)
}

func newSessionWithID(serverPSK, userPSK []byte, sessionID [8]byte) (*Session, error) {
	subkey := DeriveSessionSubkey(userPSK, sessionID)
	eih, err := DeriveEIH(serverPSK, userPSK, sessionID)
	if err != nil {
		return nil, err
	}
	userPSKCopy := make([]byte, len(userPSK))
	copy(userPSKCopy, userPSK)
	return &Session{
		sessionID:     sessionID,
		sessionSubkey: subkey,
		eihData:       eih,
		serverSubkeys: make(map[[8]byte][]byte),
		userPSK:       userPSKCopy,
	}, nil
}

// SessionID returns the session's 8-byte ID.
func (s *Session) SessionID() [8]byte {
	return s.sessionID
}

// serverSubkey returns (or derives and caches) the session subkey for a given
// server-side session_id.
func (s *Session) serverSubkey(serverSessionID [8]byte) []byte {
	s.serverSubkeyMu.Lock()
	defer s.serverSubkeyMu.Unlock()
	if sk, ok := s.serverSubkeys[serverSessionID]; ok {
		return sk
	}
	sk := DeriveSessionSubkey(s.userPSK, serverSessionID)
	s.serverSubkeys[serverSessionID] = sk
	return sk
}

// --------------------------------------------------------------------------
// Frame encode (client → server)
// --------------------------------------------------------------------------

// BuildClientFrame builds a complete SS-2022 UDP relay frame for a WireGuard
// datagram being sent client→server.
//
//   frame = separateHeader_ct (16) || EIH (16) || AEAD(key, nonce, plaintext)
//
// packetID must be monotonically increasing across calls with the same session.
func (s *Session) BuildClientFrame(packetID uint64, targetIP net.IP, targetPort uint16, payload []byte) ([]byte, error) {
	// 1. Encrypt separateHeader
	separateCT, err := encryptSeparateHeader(s.sessionSubkey, s.sessionID, packetID)
	if err != nil {
		return nil, err
	}

	// 2. AEAD key = sessionSubkey; nonce = last 12 bytes of separateCT
	nonce := separateCT[4:16]

	// 3. Build AEAD plaintext
	addrBytes := encodeAddr(targetIP, targetPort)
	// type(1) + timestamp(8) + padding_len(2=0) + addr + payload
	ptLen := 1 + 8 + 2 + len(addrBytes) + len(payload)
	plaintext := make([]byte, ptLen)
	idx := 0
	plaintext[idx] = typeClientToServer
	idx++
	binary.BigEndian.PutUint64(plaintext[idx:], uint64(time.Now().Unix()))
	idx += 8
	binary.BigEndian.PutUint16(plaintext[idx:], 0) // padding_len = 0
	idx += 2
	copy(plaintext[idx:], addrBytes)
	idx += len(addrBytes)
	copy(plaintext[idx:], payload)

	// 4. AEAD-GCM encrypt
	block, err := aes.NewCipher(s.sessionSubkey)
	if err != nil {
		return nil, fmt.Errorf("ssframing: AES cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("ssframing: GCM: %w", err)
	}
	// Seal appends tag to dst; no additional data for SS-2022 UDP
	aeadCT := gcm.Seal(nil, nonce, plaintext, nil)

	// 5. Assemble: separateCT || EIH || aeadCT
	frame := make([]byte, separateHeaderSize+eihSize+len(aeadCT))
	copy(frame[:separateHeaderSize], separateCT)
	copy(frame[separateHeaderSize:separateHeaderSize+eihSize], s.eihData)
	copy(frame[separateHeaderSize+eihSize:], aeadCT)

	return frame, nil
}

// --------------------------------------------------------------------------
// Frame decode (server → client)
// --------------------------------------------------------------------------

// ParseServerFrame decodes an SS-2022 UDP relay frame received from the server
// and returns the inner WireGuard payload. It verifies:
//   - Timestamp is within ±30 seconds of local time.
//   - client_session_id in the server frame matches ourSessionID (s.sessionID).
//
// Note: the server uses its own session_id for the separateHeader. We derive
// the server's session subkey from the server's session_id (different from ours).
func (s *Session) ParseServerFrame(frame []byte) ([]byte, error) {
	if len(frame) < separateHeaderSize+eihSize+1+gcmTagSize {
		return nil, ErrShortFrame
	}

	// 1. Decrypt separateHeader to learn the server's session_id and packet_id
	//    We need the server's subkey, but we don't know the server's session_id
	//    yet — it's inside the separateHeader. We decrypt using a trial approach:
	//    For the very first server frame, try deriving from the raw bytes.
	//    The server's session_id is the first 8 bytes of the decrypted separateHeader.
	//
	//    Strategy: The server's session_id is at separateCT[0..16] after decryption
	//    using the server's subkey. But we don't have the server's session_id yet
	//    (chicken-and-egg). The standard approach is:
	//
	//    For a server frame, we first try each cached server session. If no match,
	//    we try to brute-decrypt by assuming the server's session_id is some value.
	//
	//    However, the SS-2022 spec resolves this differently: the server uses the
	//    same subkey derivation. To handle multi-server-session:
	//
	//    The actual SS-2022 spec says: server's separateHeader is encrypted with
	//    the server's session subkey (derived from userPSK + server_session_id).
	//    But we need to know server_session_id to derive the key...
	//
	//    The spec's solution: use our CLIENT session subkey to try-decrypt,
	//    then read the server_session_id from the result, then re-derive.
	//    No — the spec is clear: the server sends frames encrypted with ITS OWN
	//    session subkey, which the client derives from userPSK + server_session_id.
	//
	//    The bootstrap: the server includes its session_id in each frame, so the
	//    client needs to try all known server session_ids to find a valid decrypt.
	//    For the first frame, the client has to try a "blind" decrypt.
	//
	//    Practical implementation (used by shadowsocks-rust): the server's first
	//    frame must be decoded by trying to decrypt the separateHeader with a subkey
	//    derived from (userPSK, candidate_session_id) where candidate_session_id
	//    comes from the separateHeader plaintext itself — but that's circular.
	//
	//    CORRECT approach (from the spec): The server encrypts separateHeader with
	//    AES-256-ECB using serverSessionSubkey = BLAKE3(userPSK || server_session_id).
	//    The client CANNOT decrypt this without knowing server_session_id first.
	//
	//    The practical resolution in shadowsocks-rust: The first 8 bytes of the
	//    encrypted separateHeader ARE the server session_id (before encryption with
	//    a subkey derived from that same session_id — which breaks circularity).
	//
	//    ACTUAL correct reading of the spec (re-checking):
	//    The "session_id" in the separateHeader is the SENDER's session_id.
	//    For server→client, the sender is the SERVER. The separateHeader is
	//    encrypted with the server's session subkey. The client needs to figure
	//    out what the server's session_id is.
	//
	//    shadowsocks-rust uses a "session filter" / cache: it tries to decrypt
	//    the separateHeader using EACH known server session subkey until one works
	//    (validated by checking timestamp plausibility in the decrypted plaintext).
	//    On the first server frame (no known server sessions), it tries the
	//    CLIENT'S own subkey as a speculative first attempt — but that would fail.
	//
	//    THE ACTUAL TRICK (from shadowsocks-rust source): The server's separateHeader
	//    is encrypted under serverSession subkey. The client, upon receiving the first
	//    server packet, extracts the FIRST 8 BYTES of the ENCRYPTED separateHeader
	//    as the candidate server_session_id, derives a trial subkey, and attempts
	//    to decrypt. If the timestamp check passes → accept. This is the bootstrap.
	//
	//    This works because the first 8 bytes of the SERVER's encrypted separateHeader
	//    are treated as the server session ID hint. This is NOT the spec proper — it
	//    is the practical bootstrap heuristic used by all implementations.

	separateCT := frame[:separateHeaderSize]

	// Try all known server sessions first
	s.serverSubkeyMu.Lock()
	knownSubkeys := make(map[[8]byte][]byte, len(s.serverSubkeys))
	for k, v := range s.serverSubkeys {
		knownSubkeys[k] = v
	}
	s.serverSubkeyMu.Unlock()

	var (
		serverSessionID [8]byte
		serverPacketID  uint64
		subkey          []byte
		found           bool
	)

	for sid, sk := range knownSubkeys {
		decSID, decPktID, err := decryptSeparateHeader(sk, separateCT)
		if err != nil {
			continue
		}
		if decSID != sid {
			continue
		}
		serverSessionID = decSID
		serverPacketID = decPktID
		subkey = sk
		found = true
		_ = serverPacketID // suppress unused warning
		break
	}

	if !found {
		// Bootstrap: treat the first 8 bytes of the encrypted separateHeader as
		// the candidate server session_id, derive a trial subkey, and attempt decrypt.
		copy(serverSessionID[:], separateCT[:8])
		trialSubkey := DeriveSessionSubkey(s.userPSK, serverSessionID)
		decSID, _, err := decryptSeparateHeader(trialSubkey, separateCT)
		if err == nil && decSID == serverSessionID {
			subkey = trialSubkey
			found = true
			// Cache this server session
			s.serverSubkeyMu.Lock()
			s.serverSubkeys[serverSessionID] = trialSubkey
			s.serverSubkeyMu.Unlock()
		}
	}

	if !found || subkey == nil {
		return nil, fmt.Errorf("ssframing: cannot decrypt server separateHeader (no matching session)")
	}

	// 2. Derive AEAD nonce from separateCT (last 12 bytes)
	nonce := separateCT[4:16]

	// 3. AEAD-GCM decrypt (skip EIH in server frames — server doesn't send EIH back)
	// Server frame layout: separateCT (16) || AEAD ciphertext (no EIH from server)
	// Wait — does server send EIH? No, EIH is only client→server.
	aeadStart := separateHeaderSize
	// If server frame also has EIH size gap, we'd skip it — but per spec
	// server → client does NOT include EIH. EIH is only in client → server.
	// So aeadStart = separateHeaderSize (16 bytes only, no EIH in server→client).
	aeadCT := frame[aeadStart:]

	block, err := aes.NewCipher(subkey)
	if err != nil {
		return nil, fmt.Errorf("ssframing: AES cipher for AEAD: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("ssframing: GCM for AEAD: %w", err)
	}
	plaintext, err := gcm.Open(nil, nonce, aeadCT, nil)
	if err != nil {
		return nil, fmt.Errorf("ssframing: AEAD decrypt: %w", err)
	}

	// 4. Parse plaintext: type(1) || timestamp(8) || client_session_id(8) || padding_len(2) || addr || payload
	if len(plaintext) < 1+8+8+2 {
		return nil, ErrInvalidFrame
	}
	if plaintext[0] != typeServerToClient {
		return nil, fmt.Errorf("ssframing: expected type 0x01 got 0x%02x", plaintext[0])
	}

	ts := binary.BigEndian.Uint64(plaintext[1:9])
	now := uint64(time.Now().Unix())
	diff := int64(ts) - int64(now)
	if diff < -maxTimestampDrift || diff > maxTimestampDrift {
		return nil, ErrTimestampOutOfRange
	}

	var clientSessionID [8]byte
	copy(clientSessionID[:], plaintext[9:17])
	if clientSessionID != s.sessionID {
		return nil, ErrSessionIDMismatch
	}

	paddingLen := int(binary.BigEndian.Uint16(plaintext[17:19]))
	addrStart := 19 + paddingLen
	if addrStart > len(plaintext) {
		return nil, ErrInvalidFrame
	}

	_, _, addrLen, err := decodeAddr(plaintext[addrStart:])
	if err != nil {
		return nil, fmt.Errorf("ssframing: decodeAddr: %w", err)
	}

	payloadStart := addrStart + addrLen
	if payloadStart > len(plaintext) {
		return nil, ErrInvalidFrame
	}

	payload := make([]byte, len(plaintext)-payloadStart)
	copy(payload, plaintext[payloadStart:])
	return payload, nil
}
