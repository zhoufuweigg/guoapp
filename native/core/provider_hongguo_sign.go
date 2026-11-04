package core

import (
	"crypto/rand"
	"encoding/binary"
	"strconv"
	"time"
)

func newHongguoDeviceID() string {
	var random [8]byte
	if _, err := rand.Read(random[:]); err != nil {
		return strconv.FormatInt(time.Now().UnixNano(), 10)
	}
	return strconv.FormatUint(1_000_000_000_000_000_000+binary.BigEndian.Uint64(random[:])%8_000_000_000_000_000_000, 10)
}
