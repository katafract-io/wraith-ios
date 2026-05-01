// SPDX-License-Identifier: MIT
//
// ssbind.go — Stealth-mode Bind for WireGuard on iOS/macOS.
//
// Two constructors:
//
//   newSSBindPassthrough()  — Phase A: delegates to StdNetBind (no SS framing).
//                             Proves the device-construction substitution point
//                             works end-to-end on a real device.
//
//   newSSBindUDP(...)       — Phase B: real SS-2022 UDP-relay framing.
//                             Every WG datagram is wrapped in a Shadowsocks-2022
//                             "2022-blake3-aes-256-gcm" UDP frame and sent to the
//                             ssservice relay at <relayHost>:<relayPort> (UDP 8443).
//                             The server decapsulates the SS frame and forwards
//                             the inner WG datagram to wg0 at 127.0.0.1:51820.
//
// Phase C (TCP+TLS+WS) and Phase D (lifecycle integration) are future work.

package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/binary"
	"fmt"
	"net"
	"net/netip"
	"sync"
	"sync/atomic"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/conn"
	"lukechampine.com/blake3"
)

// --------------------------------------------------------------------------
// ssBind — outer struct shared by passthrough and UDP modes
// --------------------------------------------------------------------------

// ssBind implements conn.Bind. When `framing` is nil it is a passthrough
// (Phase A). When non-nil it is SS-2022 UDP relay mode (Phase B).
type ssBind struct {
	// Phase A: inner standard bind (nil in Phase B)
	inner conn.Bind

	// Phase B: set when SS-2022 UDP framing is active
	framing *ssUDPFraming
}

// newSSBindPassthrough returns an ssBind with no SS framing — just a real
// stdlib UDP socket. Used in Phase A to validate substitution.
func newSSBindPassthrough() *ssBind {
	return &ssBind{inner: conn.NewStdNetBind()}
}

// Open forwards to inner bind (Phase A).
func (b *ssBind) Open(port uint16) ([]conn.ReceiveFunc, uint16, error) {
	if b.framing != nil {
		return b.framing.open(port)
	}
	return b.inner.Open(port)
}

// Close forwards to inner bind (Phase A) or shuts down the UDP socket (Phase B).
func (b *ssBind) Close() error {
	if b.framing != nil {
		return b.framing.close()
	}
	return b.inner.Close()
}

// SetMark forwards to inner bind (Phase A). Phase B no-ops on Apple platforms.
func (b *ssBind) SetMark(mark uint32) error {
	if b.framing != nil {
		return nil // iOS doesn't use socket marks; ssUDPFraming handles its own socket
	}
	return b.inner.SetMark(mark)
}

// Send forwards (Phase A) or wraps each datagram in an SS-2022 UDP frame (Phase B).
func (b *ssBind) Send(bufs [][]byte, ep conn.Endpoint) error {
	if b.framing != nil {
		return b.framing.send(bufs)
	}
	return b.inner.Send(bufs, ep)
}

// ParseEndpoint forwards (Phase A) or returns the relay endpoint (Phase B).
func (b *ssBind) ParseEndpoint(s string) (conn.Endpoint, error) {
	if b.framing != nil {
		// Phase B: the actual destination is always relayAddr on the wire.
		// We return a fake endpoint that carries the original string for
		// WireGuard's routing state, but Send always directs traffic to relayAddr.
		return &ssEndpoint{raw: s}, nil
	}
	return b.inner.ParseEndpoint(s)
}

// BatchSize returns 1 for Phase B (no batching); delegates in Phase A.
func (b *ssBind) BatchSize() int {
	if b.framing != nil {
		return 1
	}
	return b.inner.BatchSize()
}

// GetOffloadInfo forwards. AmneziaWG's `conn.Bind` interface adds this method
// (vs upstream wireguard-go) for hardware-offload diagnostics on Linux. On
// Apple platforms the inner StdNetBind returns a zero-state string. We
// prefix the result so the in-app log can see Stealth mode is active.
func (b *ssBind) GetOffloadInfo() string {
	if b.framing != nil {
		return "ssBind(udp-relay)"
	}
	return "ssBind(passthrough): " + b.inner.GetOffloadInfo()
}

// --------------------------------------------------------------------------
// ssEndpoint — fake endpoint used in Phase B
// --------------------------------------------------------------------------

// ssEndpoint implements conn.Endpoint. It carries the original string from
// ParseEndpoint so WireGuard's internal routing book-keeping (roaming, etc.)
// is satisfied, but ssBind.Send always routes to the relay regardless.
type ssEndpoint struct {
	raw string
}

func (e *ssEndpoint) ClearSrc()           {}
func (e *ssEndpoint) SrcToString() string { return "" }
func (e *ssEndpoint) DstToString() string { return e.raw }
func (e *ssEndpoint) DstToBytes() []byte  { return []byte(e.raw) }
func (e *ssEndpoint) DstIP() netip.Addr   { return netip.Addr{} }
func (e *ssEndpoint) SrcIP() netip.Addr   { return netip.Addr{} }

// --------------------------------------------------------------------------
// ssUDPFraming — Phase B: SS-2022 UDP relay over a single UDP socket
// --------------------------------------------------------------------------

// ssUDPFraming holds all state for the Phase B SS-2022 relay bind.
// It is safe for concurrent use.
type ssUDPFraming struct {
	// Relay target
	relayAddr  *net.UDPAddr
	targetIP   net.IP
	targetPort uint16

	// Key material
	serverPSK []byte
	userPSK   []byte

	// Session state — persists across Bind.Open/Close cycles to avoid
	// colliding with the server's replay window (256-packet window per session).
	// session is initialized once and reused; only the UDP socket is recycled.
	sessionOnce sync.Once
	session     *ssSession

	// UDP socket — replaced on each Open()
	mu      sync.RWMutex
	udpConn *net.UDPConn

	// Monotonically-increasing packet counter; persists across Open cycles.
	nextPacketID uint64 // accessed via atomic

	// Receive buffer pool — avoids per-packet allocation within NetworkExtension
	// memory budget (50 MB hard ceiling).
	bufPool sync.Pool
}

// ssSession holds the per-session cryptographic material.
type ssSession struct {
	sessionID    [8]byte
	sessionSubkey []byte // 32 bytes
	eihData      []byte // 16 bytes

	// Per-server-session subkey cache
	mu           sync.Mutex
	serverSubkeys map[[8]byte][]byte

	// userPSK retained for on-demand server-session subkey derivation
	userPSK []byte
}

const (
	separateHeaderSize = 16
	eihSize            = 16
	gcmTagSize         = 16

	// Maximum clock drift accepted from server timestamps (±30s)
	maxTimestampDrift = 30

	// SS-2022 ATYP values
	atypIPv4 byte = 0x01
	atypIPv6 byte = 0x04

	typeClientToServer byte = 0x00
	typeServerToClient byte = 0x01

	// Receive buffer: WG MTU is 1420; SS overhead ≤ 80 bytes; round up.
	maxSSUDPFrame = 65536

	// BLAKE3 key derivation contexts (from the SS-2022 spec)
	sessionSubkeyContext  = "shadowsocks 2022 session subkey"
	identitySubkeyContext = "shadowsocks 2022 identity subkey"
)

// newSSBindUDP returns an ssBind configured for Phase B SS-2022 UDP relay.
//
//   serverPSKHex, userPSKHex — the two halves of the combined password
//                              "SERVER_PSK:USER_PSK" from ShadowsocksConfig.
//   relayHost, relayPort     — ssservice relay endpoint (UDP 8443).
//   targetIP, targetPort     — WireGuard node endpoint (51820) embedded in SS frames.
func newSSBindUDP(serverPSK, userPSK []byte, relayHost string, relayPort uint16, targetIP net.IP, targetPort uint16) (*ssBind, error) {
	if len(serverPSK) != 32 || len(userPSK) != 32 {
		return nil, fmt.Errorf("ssframing: serverPSK and userPSK must each be 32 bytes")
	}

	relayAddr, err := net.ResolveUDPAddr("udp", fmt.Sprintf("%s:%d", relayHost, relayPort))
	if err != nil {
		return nil, fmt.Errorf("ssframing: resolve relay addr: %w", err)
	}

	serverPSKCopy := make([]byte, 32)
	userPSKCopy := make([]byte, 32)
	copy(serverPSKCopy, serverPSK)
	copy(userPSKCopy, userPSK)

	framing := &ssUDPFraming{
		relayAddr:  relayAddr,
		targetIP:   targetIP,
		targetPort: targetPort,
		serverPSK:  serverPSKCopy,
		userPSK:    userPSKCopy,
		bufPool: sync.Pool{
			New: func() interface{} {
				buf := make([]byte, maxSSUDPFrame)
				return &buf
			},
		},
	}

	return &ssBind{framing: framing}, nil
}

// initSession lazily initializes (or reuses) the SS-2022 session.
// Called from open() the first time and every subsequent Bind.Open.
// Session_id is generated once and kept for the lifetime of the framing
// object so the server's replay window is never tripped by reopen.
func (f *ssUDPFraming) initSession() error {
	var initErr error
	f.sessionOnce.Do(func() {
		var sid [8]byte
		if _, err := rand.Read(sid[:]); err != nil {
			initErr = fmt.Errorf("ssframing: rand sessionID: %w", err)
			return
		}
		sess, err := newSSSession(f.serverPSK, f.userPSK, sid)
		if err != nil {
			initErr = err
			return
		}
		f.session = sess
	})
	return initErr
}

func newSSSession(serverPSK, userPSK []byte, sessionID [8]byte) (*ssSession, error) {
	subkey := deriveSessionSubkey(userPSK, sessionID)
	eih, err := deriveEIH(serverPSK, userPSK, sessionID)
	if err != nil {
		return nil, err
	}
	userPSKCopy := make([]byte, len(userPSK))
	copy(userPSKCopy, userPSK)
	return &ssSession{
		sessionID:     sessionID,
		sessionSubkey: subkey,
		eihData:       eih,
		serverSubkeys: make(map[[8]byte][]byte),
		userPSK:       userPSKCopy,
	}, nil
}

// --------------------------------------------------------------------------
// Key derivation
// --------------------------------------------------------------------------

func deriveSessionSubkey(psk []byte, sessionID [8]byte) []byte {
	material := make([]byte, len(psk)+8)
	copy(material, psk)
	copy(material[len(psk):], sessionID[:])
	out := make([]byte, 32)
	blake3.DeriveKey(out, sessionSubkeyContext, material)
	return out
}

func deriveEIH(serverPSK, userPSK []byte, sessionID [8]byte) ([]byte, error) {
	// eihKey = BLAKE3.deriveKey(identitySubkeyContext, serverPSK || sessionID)[0..32]
	material := make([]byte, len(serverPSK)+8)
	copy(material, serverPSK)
	copy(material[len(serverPSK):], sessionID[:])
	eihKey := make([]byte, 32)
	blake3.DeriveKey(eihKey, identitySubkeyContext, material)

	// userIdentity = BLAKE3(userPSK)[0..16]
	userPSKHash := blake3.Sum256(userPSK)
	userIdentity := userPSKHash[:16]

	// AES-256-ECB encrypt the 16-byte identity block
	block, err := aes.NewCipher(eihKey)
	if err != nil {
		return nil, fmt.Errorf("ssframing: deriveEIH AES: %w", err)
	}
	eih := make([]byte, 16)
	block.Encrypt(eih, userIdentity)
	return eih, nil
}

// --------------------------------------------------------------------------
// Separate header encrypt/decrypt
// --------------------------------------------------------------------------

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

func decryptSeparateHeader(subkey, ciphertext []byte) ([8]byte, uint64, error) {
	if len(ciphertext) < 16 {
		return [8]byte{}, 0, fmt.Errorf("ssframing: separateHeader too short")
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
// Server session subkey cache
// --------------------------------------------------------------------------

func (s *ssSession) serverSubkey(serverSessionID [8]byte) []byte {
	s.mu.Lock()
	defer s.mu.Unlock()
	if sk, ok := s.serverSubkeys[serverSessionID]; ok {
		return sk
	}
	sk := deriveSessionSubkey(s.userPSK, serverSessionID)
	s.serverSubkeys[serverSessionID] = sk
	return sk
}

// --------------------------------------------------------------------------
// Address encode/decode
// --------------------------------------------------------------------------

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

func decodeAddrLen(buf []byte) (int, error) {
	if len(buf) < 1 {
		return 0, fmt.Errorf("ssframing: empty addr buffer")
	}
	switch buf[0] {
	case atypIPv4:
		if len(buf) < 7 {
			return 0, fmt.Errorf("ssframing: IPv4 addr truncated")
		}
		return 7, nil
	case atypIPv6:
		if len(buf) < 19 {
			return 0, fmt.Errorf("ssframing: IPv6 addr truncated")
		}
		return 19, nil
	default:
		return 0, fmt.Errorf("ssframing: unknown ATYP 0x%02x", buf[0])
	}
}

// --------------------------------------------------------------------------
// open / close / send / receive
// --------------------------------------------------------------------------

func (f *ssUDPFraming) open(port uint16) ([]conn.ReceiveFunc, uint16, error) {
	// Ensure session is initialized (idempotent after first call)
	if err := f.initSession(); err != nil {
		return nil, 0, err
	}

	// Open a new unconnected UDP socket bound to a random port.
	// We use an unconnected socket so we can WriteToUDP to relayAddr —
	// this allows clean rebinding on network roaming events.
	udpConn, err := net.ListenUDP("udp", &net.UDPAddr{Port: int(port)})
	if err != nil {
		// If the caller requested a specific port and it's busy, try 0.
		if port != 0 {
			udpConn, err = net.ListenUDP("udp", &net.UDPAddr{Port: 0})
		}
		if err != nil {
			return nil, 0, fmt.Errorf("ssframing: ListenUDP: %w", err)
		}
	}

	f.mu.Lock()
	f.udpConn = udpConn
	f.mu.Unlock()

	actualAddr := udpConn.LocalAddr().(*net.UDPAddr)
	actualPort := uint16(actualAddr.Port)

	recvFn := f.makeReceiveFunc(udpConn)
	return []conn.ReceiveFunc{recvFn}, actualPort, nil
}

func (f *ssUDPFraming) close() error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.udpConn != nil {
		err := f.udpConn.Close()
		f.udpConn = nil
		return err
	}
	return nil
}

// send wraps each WG datagram in an SS-2022 UDP frame and writes it to relayAddr.
func (f *ssUDPFraming) send(bufs [][]byte) error {
	sess := f.session // session is always valid after open()

	f.mu.RLock()
	udpConn := f.udpConn
	f.mu.RUnlock()
	if udpConn == nil {
		return fmt.Errorf("ssframing: send on closed bind")
	}

	for _, payload := range bufs {
		packetID := atomic.AddUint64(&f.nextPacketID, 1) - 1

		frame, err := buildClientFrame(sess, packetID, f.targetIP, f.targetPort, payload)
		if err != nil {
			return fmt.Errorf("ssframing: buildClientFrame: %w", err)
		}

		if _, err := udpConn.WriteToUDP(frame, f.relayAddr); err != nil {
			return fmt.Errorf("ssframing: WriteToUDP: %w", err)
		}
	}
	return nil
}

// makeReceiveFunc returns the conn.ReceiveFunc for this UDP socket.
// WireGuard calls this with a batch slice; we fill up to len(packets) entries.
func (f *ssUDPFraming) makeReceiveFunc(udpConn *net.UDPConn) conn.ReceiveFunc {
	sess := f.session
	relayEP := &ssEndpoint{raw: f.relayAddr.String()}

	return func(packets [][]byte, sizes []int, eps []conn.Endpoint) (int, error) {
		// Read one UDP datagram per call (BatchSize returns 1)
		bufPtr := f.bufPool.Get().(*[]byte)
		buf := *bufPtr
		defer func() {
			f.bufPool.Put(bufPtr)
		}()

		n, _, err := udpConn.ReadFromUDP(buf)
		if err != nil {
			return 0, err
		}
		if n == 0 {
			return 0, nil
		}

		payload, err := parseServerFrame(sess, buf[:n])
		if err != nil {
			// Log and skip this frame — do not propagate to WireGuard as an
			// error (which would tear down the bind). Bad frames can be noise.
			// WireGuard will retry on the next receive call.
			_ = err // caller gets 0 valid packets; WG loops
			return 0, nil
		}

		if len(packets) == 0 {
			return 0, nil
		}

		// Copy payload into the WG-supplied buffer
		dst := packets[0]
		if len(payload) > len(dst) {
			// Payload doesn't fit in the provided buffer — drop and continue.
			return 0, nil
		}
		copy(dst, payload)
		sizes[0] = len(payload)
		eps[0] = relayEP
		return 1, nil
	}
}

// --------------------------------------------------------------------------
// Frame construction (client → server)
// --------------------------------------------------------------------------

func buildClientFrame(sess *ssSession, packetID uint64, targetIP net.IP, targetPort uint16, payload []byte) ([]byte, error) {
	// 1. Encrypt separateHeader: AES-256-ECB(subkey, sessionID || packetID)
	separateCT, err := encryptSeparateHeader(sess.sessionSubkey, sess.sessionID, packetID)
	if err != nil {
		return nil, err
	}

	// 2. AEAD key = sessionSubkey; nonce = last 12 bytes of separateCT
	nonce := separateCT[4:16]

	// 3. Build AEAD plaintext:
	//    type(1=0x00) || timestamp(8 BE) || padding_len(2 BE=0) || ATYP+addr+port || payload
	addrBytes := encodeAddr(targetIP, targetPort)
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

	// 4. AES-256-GCM encrypt
	block, err := aes.NewCipher(sess.sessionSubkey)
	if err != nil {
		return nil, fmt.Errorf("ssframing: buildClientFrame AES: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("ssframing: buildClientFrame GCM: %w", err)
	}
	aeadCT := gcm.Seal(nil, nonce, plaintext, nil)

	// 5. Assemble: separateCT(16) || EIH(16) || aeadCT
	frame := make([]byte, separateHeaderSize+eihSize+len(aeadCT))
	copy(frame[:separateHeaderSize], separateCT)
	copy(frame[separateHeaderSize:separateHeaderSize+eihSize], sess.eihData)
	copy(frame[separateHeaderSize+eihSize:], aeadCT)

	return frame, nil
}

// --------------------------------------------------------------------------
// Frame parsing (server → client)
// --------------------------------------------------------------------------

func parseServerFrame(sess *ssSession, frame []byte) ([]byte, error) {
	// Minimum: separateHeader(16) + aeadCT(≥ type(1)+ts(8)+client_sid(8)+padding(2)+addr_min(7)+tag(16)) = 58
	if len(frame) < separateHeaderSize+1+gcmTagSize {
		return nil, fmt.Errorf("ssframing: frame too short (%d bytes)", len(frame))
	}

	separateCT := frame[:separateHeaderSize]

	// ---- Decode server's separateHeader ----
	// The server uses its own session_id to derive its own session subkey.
	// We don't know the server's session_id until we decrypt the separateHeader —
	// which requires knowing the server's session subkey first. Circular.
	//
	// The practical bootstrap (used by shadowsocks-rust):
	//   1. Extract the first 8 bytes of the ENCRYPTED separateHeader as a
	//      candidate server_session_id.
	//   2. Derive a trial subkey from (userPSK, candidate_server_session_id).
	//   3. Decrypt the separateHeader; verify the decrypted session_id matches
	//      the candidate. If yes → we have the correct server session subkey.
	//
	// For subsequent frames from the same server session, the subkey is cached.
	var (
		serverSessionID [8]byte
		subkey          []byte
		found           bool
	)

	// Try all cached server sessions first (fast path after bootstrap)
	sess.mu.Lock()
	for sid, sk := range sess.serverSubkeys {
		decSID, _, err := decryptSeparateHeader(sk, separateCT)
		if err == nil && decSID == sid {
			serverSessionID = decSID
			subkey = sk
			found = true
			break
		}
	}
	sess.mu.Unlock()

	if !found {
		// Bootstrap: treat the first 8 bytes of encrypted separateHeader as
		// the candidate server_session_id.
		copy(serverSessionID[:], separateCT[:8])
		trialSubkey := deriveSessionSubkey(sess.userPSK, serverSessionID)
		decSID, _, err := decryptSeparateHeader(trialSubkey, separateCT)
		if err == nil && decSID == serverSessionID {
			subkey = trialSubkey
			found = true
			sess.mu.Lock()
			sess.serverSubkeys[serverSessionID] = trialSubkey
			sess.mu.Unlock()
		}
	}

	if !found {
		return nil, fmt.Errorf("ssframing: cannot resolve server session subkey")
	}

	// ---- AEAD decrypt ----
	// Server → client frame: separateCT(16) || aeadCT (no EIH from server)
	nonce := separateCT[4:16]
	aeadCT := frame[separateHeaderSize:]

	block, err := aes.NewCipher(subkey)
	if err != nil {
		return nil, fmt.Errorf("ssframing: parseServerFrame AES: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("ssframing: parseServerFrame GCM: %w", err)
	}
	plaintext, err := gcm.Open(nil, nonce, aeadCT, nil)
	if err != nil {
		return nil, fmt.Errorf("ssframing: parseServerFrame AEAD decrypt: %w", err)
	}

	// ---- Parse server→client plaintext ----
	// type(1=0x01) || timestamp(8) || client_session_id(8) || padding_len(2) || ATYP+addr+port || payload
	if len(plaintext) < 1+8+8+2 {
		return nil, fmt.Errorf("ssframing: server plaintext too short")
	}
	if plaintext[0] != typeServerToClient {
		return nil, fmt.Errorf("ssframing: expected type 0x01, got 0x%02x", plaintext[0])
	}

	ts := binary.BigEndian.Uint64(plaintext[1:9])
	now := uint64(time.Now().Unix())
	diff := int64(ts) - int64(now)
	if diff < -maxTimestampDrift || diff > maxTimestampDrift {
		return nil, fmt.Errorf("ssframing: timestamp drift %d exceeds ±%d", diff, maxTimestampDrift)
	}

	var clientSID [8]byte
	copy(clientSID[:], plaintext[9:17])
	if clientSID != sess.sessionID {
		return nil, fmt.Errorf("ssframing: client_session_id mismatch")
	}

	paddingLen := int(binary.BigEndian.Uint16(plaintext[17:19]))
	addrStart := 19 + paddingLen
	if addrStart >= len(plaintext) {
		return nil, fmt.Errorf("ssframing: addr region out of bounds")
	}

	addrLen, err := decodeAddrLen(plaintext[addrStart:])
	if err != nil {
		return nil, fmt.Errorf("ssframing: decodeAddr: %w", err)
	}

	payloadStart := addrStart + addrLen
	if payloadStart > len(plaintext) {
		return nil, fmt.Errorf("ssframing: payload region out of bounds")
	}

	result := make([]byte, len(plaintext)-payloadStart)
	copy(result, plaintext[payloadStart:])
	return result, nil
}
