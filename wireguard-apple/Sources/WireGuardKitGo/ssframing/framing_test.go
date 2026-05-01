// SPDX-License-Identifier: MIT
//
// ssframing/framing_test.go — Round-trip unit tests for SS-2022 UDP framing.
//
// Run with: go test ./ssframing/... (from the WireGuardKitGo directory)

package ssframing

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"encoding/binary"
	"net"
	"testing"
	"time"
)

// -------------------------------------------------------------------------
// Helpers
// -------------------------------------------------------------------------

// generate 32 deterministic bytes for a test key
func testKey(seed byte) []byte {
	k := make([]byte, 32)
	for i := range k {
		k[i] = seed + byte(i)
	}
	return k
}

// -------------------------------------------------------------------------
// Key derivation tests
// -------------------------------------------------------------------------

func TestDeriveSessionSubkeyDeterministic(t *testing.T) {
	psk := testKey(0x01)
	var sid [8]byte
	for i := range sid {
		sid[i] = byte(0x10 + i)
	}
	sk1 := DeriveSessionSubkey(psk, sid)
	sk2 := DeriveSessionSubkey(psk, sid)
	if !bytes.Equal(sk1, sk2) {
		t.Fatal("DeriveSessionSubkey not deterministic")
	}
	if len(sk1) != 32 {
		t.Fatalf("expected 32 bytes, got %d", len(sk1))
	}
}

func TestDeriveSessionSubkeyDistinct(t *testing.T) {
	psk := testKey(0x01)
	var sid1, sid2 [8]byte
	sid1[0] = 0xAA
	sid2[0] = 0xBB
	sk1 := DeriveSessionSubkey(psk, sid1)
	sk2 := DeriveSessionSubkey(psk, sid2)
	if bytes.Equal(sk1, sk2) {
		t.Fatal("different sessionIDs produced same subkey")
	}
}

func TestDeriveEIHDeterministic(t *testing.T) {
	serverPSK := testKey(0x01)
	userPSK := testKey(0x02)
	var sid [8]byte
	sid[0] = 0xCA
	eih1, err := DeriveEIH(serverPSK, userPSK, sid)
	if err != nil {
		t.Fatalf("DeriveEIH: %v", err)
	}
	eih2, err := DeriveEIH(serverPSK, userPSK, sid)
	if err != nil {
		t.Fatalf("DeriveEIH: %v", err)
	}
	if !bytes.Equal(eih1, eih2) {
		t.Fatal("DeriveEIH not deterministic")
	}
	if len(eih1) != 16 {
		t.Fatalf("expected 16 bytes, got %d", len(eih1))
	}
}

func TestDeriveEIHDistinctForDifferentUserPSK(t *testing.T) {
	serverPSK := testKey(0x01)
	userPSK1 := testKey(0x02)
	userPSK2 := testKey(0x03)
	var sid [8]byte
	eih1, _ := DeriveEIH(serverPSK, userPSK1, sid)
	eih2, _ := DeriveEIH(serverPSK, userPSK2, sid)
	if bytes.Equal(eih1, eih2) {
		t.Fatal("different userPSKs should produce different EIH values")
	}
}

// -------------------------------------------------------------------------
// Frame size / structure tests
// -------------------------------------------------------------------------

func TestClientFrameStructure(t *testing.T) {
	serverPSK := testKey(0x01)
	userPSK := testKey(0x02)

	sess, err := NewSession(serverPSK, userPSK)
	if err != nil {
		t.Fatalf("NewSession: %v", err)
	}

	targetIP := net.ParseIP("87.99.128.159")
	payload := []byte("hello wireguard packet")

	frame, err := sess.BuildClientFrame(0, targetIP, 51820, payload)
	if err != nil {
		t.Fatalf("BuildClientFrame: %v", err)
	}

	// Frame = separateHeader(16) + EIH(16) + AEAD(plaintext) + tag(16)
	// plaintext = type(1) + ts(8) + padding_len(2) + ATYP(1) + IPv4(4) + port(2) + payload
	expectedPlaintextLen := 1 + 8 + 2 + 1 + 4 + 2 + len(payload)
	expectedFrameLen := 16 + 16 + expectedPlaintextLen + 16 // separateHeader + EIH + plaintext + GCM tag

	if len(frame) != expectedFrameLen {
		t.Fatalf("expected frame length %d, got %d", expectedFrameLen, len(frame))
	}
}

func TestClientFrameIPv6(t *testing.T) {
	serverPSK := testKey(0x01)
	userPSK := testKey(0x02)

	sess, err := NewSession(serverPSK, userPSK)
	if err != nil {
		t.Fatalf("NewSession: %v", err)
	}

	targetIP := net.ParseIP("2001:db8::1")
	payload := []byte("ipv6 test packet")

	frame, err := sess.BuildClientFrame(42, targetIP, 51820, payload)
	if err != nil {
		t.Fatalf("BuildClientFrame IPv6: %v", err)
	}

	// Frame = separateHeader(16) + EIH(16) + AEAD(plaintext) + tag(16)
	// plaintext with IPv6: type(1)+ts(8)+padding(2)+ATYP(1)+IPv6(16)+port(2)+payload
	expectedPlaintextLen := 1 + 8 + 2 + 1 + 16 + 2 + len(payload)
	expectedFrameLen := 16 + 16 + expectedPlaintextLen + 16

	if len(frame) != expectedFrameLen {
		t.Fatalf("IPv6 frame: expected %d, got %d", expectedFrameLen, len(frame))
	}
}

// -------------------------------------------------------------------------
// Server-frame simulation helpers
// -------------------------------------------------------------------------

// buildServerFrame builds a fake server→client SS-2022 frame (no EIH) that
// mimics what ssservice would send back. Used to test ParseServerFrame.
func buildServerFrame(t *testing.T, clientSess *Session, userPSK []byte, innerPayload []byte) []byte {
	t.Helper()

	// Server picks its own session_id (deterministic in tests)
	var serverSessID [8]byte
	serverSessID[0] = 0xDE
	serverSessID[1] = 0xAD

	serverSubkey := DeriveSessionSubkey(userPSK, serverSessID)

	// Encrypt server's separateHeader
	separateCT, err := encryptSeparateHeader(serverSubkey, serverSessID, 0)
	if err != nil {
		t.Fatalf("buildServerFrame encryptSeparateHeader: %v", err)
	}

	nonce := separateCT[4:16]

	// Build server→client AEAD plaintext:
	// type(1=0x01) || timestamp(8) || client_session_id(8) || padding_len(2=0) || ATYP || addr || payload
	clientSessionID := clientSess.SessionID()
	// Use "10.10.11.1:51820" as the source address field in server frame
	srcIP := net.ParseIP("10.10.11.1")
	addrBytes := encodeAddr(srcIP, 51820)

	ptLen := 1 + 8 + 8 + 2 + len(addrBytes) + len(innerPayload)
	plaintext := make([]byte, ptLen)
	idx := 0
	plaintext[idx] = typeServerToClient
	idx++
	binary.BigEndian.PutUint64(plaintext[idx:], uint64(time.Now().Unix()))
	idx += 8
	copy(plaintext[idx:], clientSessionID[:])
	idx += 8
	binary.BigEndian.PutUint16(plaintext[idx:], 0) // padding_len = 0
	idx += 2
	copy(plaintext[idx:], addrBytes)
	idx += len(addrBytes)
	copy(plaintext[idx:], innerPayload)

	// AEAD encrypt
	block, err := aes.NewCipher(serverSubkey)
	if err != nil {
		t.Fatalf("buildServerFrame AES: %v", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		t.Fatalf("buildServerFrame GCM: %v", err)
	}
	aeadCT := gcm.Seal(nil, nonce, plaintext, nil)

	// Frame: separateCT (16) || aeadCT (no EIH in server→client)
	frame := make([]byte, 16+len(aeadCT))
	copy(frame[:16], separateCT)
	copy(frame[16:], aeadCT)
	return frame
}

// -------------------------------------------------------------------------
// Round-trip tests
// -------------------------------------------------------------------------

// TestServerFrameDecode builds a fake server response and verifies
// ParseServerFrame recovers the inner payload correctly.
func TestServerFrameDecode(t *testing.T) {
	serverPSK := testKey(0x01)
	userPSK := testKey(0x02)

	clientSess, err := NewSession(serverPSK, userPSK)
	if err != nil {
		t.Fatalf("NewSession: %v", err)
	}

	original := []byte("handshake response bytes from WireGuard")
	serverFrame := buildServerFrame(t, clientSess, userPSK, original)

	decoded, err := clientSess.ParseServerFrame(serverFrame)
	if err != nil {
		t.Fatalf("ParseServerFrame: %v", err)
	}

	if !bytes.Equal(decoded, original) {
		t.Fatalf("payload mismatch: got %q, want %q", decoded, original)
	}
}

// TestMultipleServerFrames verifies the server session subkey cache is
// reused for subsequent frames (no re-derivation needed after first).
func TestMultipleServerFrames(t *testing.T) {
	serverPSK := testKey(0x10)
	userPSK := testKey(0x20)

	clientSess, err := NewSession(serverPSK, userPSK)
	if err != nil {
		t.Fatalf("NewSession: %v", err)
	}

	for i := 0; i < 5; i++ {
		payload := []byte{byte(i), byte(i + 1), byte(i + 2)}
		frame := buildServerFrame(t, clientSess, userPSK, payload)
		decoded, err := clientSess.ParseServerFrame(frame)
		if err != nil {
			t.Fatalf("frame %d ParseServerFrame: %v", i, err)
		}
		if !bytes.Equal(decoded, payload) {
			t.Fatalf("frame %d payload mismatch", i)
		}
	}
}

// TestClientFramePacketIDIncrement verifies two consecutive frames have
// distinct separateHeaders (because packet_id differs).
func TestClientFramePacketIDIncrement(t *testing.T) {
	serverPSK := testKey(0x01)
	userPSK := testKey(0x02)

	sess, err := NewSession(serverPSK, userPSK)
	if err != nil {
		t.Fatalf("NewSession: %v", err)
	}
	ip := net.ParseIP("1.2.3.4")
	f0, _ := sess.BuildClientFrame(0, ip, 51820, []byte("a"))
	f1, _ := sess.BuildClientFrame(1, ip, 51820, []byte("a"))

	// separateHeader is first 16 bytes — should differ because packet_id differs
	if bytes.Equal(f0[:16], f1[:16]) {
		t.Fatal("separateHeaders for packet_id=0 and packet_id=1 are identical")
	}
}

// -------------------------------------------------------------------------
// Address encode/decode tests
// -------------------------------------------------------------------------

func TestAddrEncodeDecodeIPv4(t *testing.T) {
	ip := net.ParseIP("192.168.1.50")
	port := uint16(12345)
	encoded := encodeAddr(ip, port)
	if len(encoded) != 7 {
		t.Fatalf("IPv4 encodeAddr: expected 7 bytes, got %d", len(encoded))
	}
	gotIP, gotPort, n, err := decodeAddr(encoded)
	if err != nil {
		t.Fatalf("decodeAddr: %v", err)
	}
	if n != 7 {
		t.Fatalf("decodeAddr consumed %d bytes, want 7", n)
	}
	if !gotIP.Equal(ip) {
		t.Fatalf("IP mismatch: got %v, want %v", gotIP, ip)
	}
	if gotPort != port {
		t.Fatalf("port mismatch: got %d, want %d", gotPort, port)
	}
}

func TestAddrEncodeDecodeIPv6(t *testing.T) {
	ip := net.ParseIP("2001:db8::dead:beef")
	port := uint16(51820)
	encoded := encodeAddr(ip, port)
	if len(encoded) != 19 {
		t.Fatalf("IPv6 encodeAddr: expected 19 bytes, got %d", len(encoded))
	}
	gotIP, gotPort, n, err := decodeAddr(encoded)
	if err != nil {
		t.Fatalf("decodeAddr: %v", err)
	}
	if n != 19 {
		t.Fatalf("decodeAddr consumed %d bytes, want 19", n)
	}
	if !gotIP.Equal(ip) {
		t.Fatalf("IPv6 mismatch: got %v, want %v", gotIP, ip)
	}
	if gotPort != port {
		t.Fatalf("port mismatch: got %d, want %d", gotPort, port)
	}
}

// -------------------------------------------------------------------------
// Session ID persistence tests
// -------------------------------------------------------------------------

func TestSessionIDPersistence(t *testing.T) {
	serverPSK := testKey(0x01)
	userPSK := testKey(0x02)
	var wantID [8]byte
	for i := range wantID {
		wantID[i] = byte(0x42 + i)
	}
	sess, err := NewSessionWithID(serverPSK, userPSK, wantID)
	if err != nil {
		t.Fatalf("NewSessionWithID: %v", err)
	}
	if sess.SessionID() != wantID {
		t.Fatalf("session ID mismatch: got %v, want %v", sess.SessionID(), wantID)
	}
}

// TestEIHInClientFrame verifies the EIH block at bytes [16..32] is non-zero
// (i.e., it was actually computed and embedded).
func TestEIHInClientFrame(t *testing.T) {
	serverPSK := testKey(0x01)
	userPSK := testKey(0x02)

	sess, err := NewSession(serverPSK, userPSK)
	if err != nil {
		t.Fatalf("NewSession: %v", err)
	}
	frame, err := sess.BuildClientFrame(0, net.ParseIP("1.2.3.4"), 51820, []byte("test"))
	if err != nil {
		t.Fatalf("BuildClientFrame: %v", err)
	}
	eih := frame[16:32]
	allZero := true
	for _, b := range eih {
		if b != 0 {
			allZero = false
			break
		}
	}
	if allZero {
		t.Fatal("EIH bytes are all zero — EIH was not embedded in the frame")
	}
}
