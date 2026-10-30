package core

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/md5"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"math/bits"
	"net/http"
	"strconv"
	"time"
)

type hongguoPlayerNonce [11]byte

func newHongguoPlayerNonce() (hongguoPlayerNonce, error) {
	var nonce hongguoPlayerNonce
	_, err := rand.Read(nonce[:])
	return nonce, err
}

func signHongguoPlayerRequest(request *http.Request, body []byte, now time.Time) {
	stamp := uint32(now.Unix())
	queryHash := md5.Sum([]byte(request.URL.RawQuery))
	var payload [20]byte
	copy(payload[:4], queryHash[:4])
	if body != nil {
		bodyHash := md5.Sum(body)
		copy(payload[4:8], bodyHash[:4])
		request.Header.Set("X-SS-STUB", fmt.Sprintf("%X", bodyHash))
	}
	copy(payload[12:16], []byte{0, 6, 11, 28})
	binary.BigEndian.PutUint32(payload[16:], stamp)
	key := [...]byte{0x44, 0xb9, 0xb9, 0xd9, 0xa4, 0xae, 0xf9, 0xfc, 0xa4, 0x93, 0xaa, 0x75, 0x7c, 0xa3, 0xc2, 0xc4, 0xa4, 0x96, 0x93, 0x8f}
	for index := range payload {
		payload[index] ^= key[index]
	}
	for index := range payload {
		mixed := bits.RotateLeft8(payload[index], 4) ^ payload[(index+1)%len(payload)]
		payload[index] = bits.Reverse8(mixed) ^ 0xff ^ byte(len(payload))
	}
	signature := append([]byte{0x84, 0x04, 0x40, 0x1c, 0, 0}, payload[:]...)
	request.Header.Set("X-Khronos", strconv.FormatUint(uint64(stamp), 10))
	request.Header.Set("X-Gorgon", hex.EncodeToString(signature))
	request.Header.Set("X-SS-Req-Ticket", strconv.FormatInt(now.UnixMilli(), 10))

	nonce, err := newHongguoPlayerNonce()
	if err != nil {
		return
	}
	request.Header.Set("X-Argus", hongguoPlayerArgus(request.URL.RawQuery, body, stamp, request.URL.Query().Get("device_id"), nonce))
	request.Header.Set("X-Ladon", hongguoPlayerLadon(request.URL.Query().Get("aid"), stamp, nonce[2:6]))
}

func hongguoPlayerArgus(query string, body []byte, timestamp uint32, deviceID string, nonce hongguoPlayerNonce) string {
	key, _ := hex.DecodeString("ac1adaae95a7af94a5114ab3b3a97dd80050aa0a39314c40528caec95256c28c")
	varint := func(message []byte, field, value uint64) []byte {
		message = binary.AppendUvarint(message, field*8)
		return binary.AppendUvarint(message, value)
	}
	bytesField := func(message []byte, field uint64, value []byte) []byte {
		message = binary.AppendUvarint(message, field*8+2)
		message = binary.AppendUvarint(message, uint64(len(value)))
		return append(message, value...)
	}
	bodyHash := hongguoSM3(make([]byte, 16))
	if body != nil {
		stub := md5.Sum(body)
		bodyHash = hongguoSM3(stub[:])
	}
	queryHash := hongguoSM3([]byte(query))
	counters := varint(varint(varint(varint(nil, 1, 1), 2, 1), 3, 1), 7, 3348294860)
	environment := bytesField(nil, 1, []byte("25053RT47C"))
	environment = bytesField(environment, 2, []byte("16"))
	environment = bytesField(environment, 3, []byte("update_64"))
	environment = varint(environment, 4, 2147483648)
	message := varint(nil, 1, 0x20200929*2)
	message = varint(message, 2, 2)
	message = varint(message, 3, uint64(binary.LittleEndian.Uint32(nonce[6:10])&0x7fffffff))
	message = bytesField(message, 4, []byte("8662"))
	message = bytesField(message, 5, []byte(deviceID))
	message = bytesField(message, 6, []byte("1611921764"))
	message = bytesField(message, 7, []byte("7.3.5.32"))
	message = bytesField(message, 8, []byte("v04.07.01-ml-android"))
	message = varint(message, 9, 135135744)
	message = bytesField(message, 10, make([]byte, 8))
	message = varint(message, 11, 0)
	message = varint(message, 12, uint64(timestamp)*2)
	message = bytesField(message, 13, bodyHash[:6])
	message = bytesField(message, 14, queryHash[:6])
	message = bytesField(message, 15, counters)
	message = bytesField(message, 16, nil)
	message = bytesField(message, 20, []byte("none"))
	message = varint(message, 21, 738)
	message = bytesField(message, 23, environment)
	message = varint(message, 25, 2)
	data := hongguoCommentPad(message)
	seed := append(append(append([]byte(nil), key...), 0x3c, 0xcc, 0x56, 0x7b), key...)
	derived := hongguoSM3(seed)
	var rounds [72]uint64
	for i := 0; i < 4; i++ {
		rounds[i] = binary.LittleEndian.Uint64(derived[i*8:])
	}
	for i := 4; i < len(rounds); i++ {
		mixed := bits.RotateLeft64(rounds[i-1], -3) ^ rounds[i-3]
		mixed ^= bits.RotateLeft64(mixed, -1)
		rounds[i] = ^rounds[i-4] ^ mixed ^ (uint64(0x3dc94c3a046d678b)>>uint((i-4)%62))&1 ^ 3
	}
	for offset := 0; offset < len(data); offset += 16 {
		left, right := binary.LittleEndian.Uint64(data[offset:]), binary.LittleEndian.Uint64(data[offset+8:])
		for _, round := range rounds {
			left, right = right, left^(bits.RotateLeft64(right, 1)&bits.RotateLeft64(right, 8))^bits.RotateLeft64(right, 2)^round
		}
		binary.LittleEndian.PutUint64(data[offset:], left)
		binary.LittleEndian.PutUint64(data[offset+8:], right)
	}
	xor := []byte{0xd0, 0x4f, 0xfd, 0xff, 0xd0, 0x4f, 0xfd, 0xff}
	for i := range data {
		data[i] ^= xor[i%8]
	}
	data = append(xor, data...)
	for left, right := 0, len(data)-1; left < right; left, right = left+1, right-1 {
		data[left], data[right] = data[right], data[left]
	}
	container := append([]byte{0xa6, 0xe7, 0x83, 0xee, 0x70, 0x01, 0x10, 0x09, 0x18}, data...)
	container = hongguoCommentPad(append(container, 0x56, 0x7b))
	aesKey, iv := md5.Sum(key[:16]), md5.Sum(key[16:])
	block, _ := aes.NewCipher(aesKey[:])
	cipher.NewCBCEncrypter(block, iv[:]).CryptBlocks(container, container)
	return base64.StdEncoding.EncodeToString(append([]byte{0x3c, 0xcc}, container...))
}

func hongguoPlayerLadon(aid string, timestamp uint32, prefix []byte) string {
	hash := md5.Sum(append(append([]byte(nil), prefix...), aid...))
	digest := []byte(hex.EncodeToString(hash[:]))
	left, right := binary.LittleEndian.Uint64(digest), binary.LittleEndian.Uint64(digest[8:])
	queue := []uint64{binary.LittleEndian.Uint64(digest[16:]), binary.LittleEndian.Uint64(digest[24:])}
	var keys [34]uint64
	for i := range keys {
		keys[i] = left
		mixed := (bits.RotateLeft64(right, -8) + left) ^ uint64(i)
		queue = append(queue, mixed)
		left = mixed ^ bits.RotateLeft64(left, 3)
		right, queue = queue[0], queue[1:]
	}
	payload := []byte(strconv.FormatUint(uint64(timestamp), 10) + "-1611921764-" + aid)
	data := hongguoCommentPad(payload)
	for offset := 0; offset < len(data); offset += 16 {
		left, right := binary.LittleEndian.Uint64(data[offset:]), binary.LittleEndian.Uint64(data[offset+8:])
		for _, key := range keys {
			right = key ^ (left + bits.RotateLeft64(right, -8))
			left = right ^ bits.RotateLeft64(left, 3)
		}
		binary.LittleEndian.PutUint64(data[offset:], left)
		binary.LittleEndian.PutUint64(data[offset+8:], right)
	}
	return base64.StdEncoding.EncodeToString(append(append([]byte(nil), prefix...), data...))
}
