package core

// 红果 App 接口六签名头（x-gorgon / x-khronos / x-ladon / x-argus / x-helios / x-medusa）
// 纯代码实现，字节级对齐参考实现（hongguo-web 的 pure-sign.js，移植自
// jackotom/hongguo-drama → woshishiq1/drpys → N3urda/hongguoTV，原版用 unidbg
// 模拟 libmetasec_ml.so 计算同样的六个头）。
//
// 语义对齐约定：
//   - JS 的 32 位有符号运算（`| 0`、`>>>`、`~`）统一用 Go uint32 承接，按模 2^32 运算；
//   - JS `rotl/ror` 的 n 先 `& 31`（`& 63`）再移位；
//   - JS 数组越界读返回 undefined（位运算中等价 0）、越界写静默忽略；
//   - Java/JS long 的 64 位运算用 uint64 承接。

import (
	"crypto/md5"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"math"
	"math/bits"
	"strconv"
	"strings"
	"time"
)

// ==================== 基础位运算 ====================

func hgConcat(parts ...[]byte) []byte {
	size := 0
	for _, part := range parts {
		size += len(part)
	}
	out := make([]byte, 0, size)
	for _, part := range parts {
		out = append(out, part...)
	}
	return out
}

func hgLe32(v uint32) []byte {
	out := make([]byte, 4)
	binary.LittleEndian.PutUint32(out, v)
	return out
}

func hgBe32(v uint32) []byte {
	out := make([]byte, 4)
	binary.BigEndian.PutUint32(out, v)
	return out
}

func hgReadLe32(b []byte, off int) uint32 {
	if off+4 > len(b) {
		return 0
	}
	return binary.LittleEndian.Uint32(b[off:])
}

func hgReadBe32(b []byte, off int) uint32 {
	if off+4 > len(b) {
		return 0
	}
	return binary.BigEndian.Uint32(b[off:])
}

func hgPutLe32(b []byte, off int, v uint32) {
	if off+4 <= len(b) {
		binary.LittleEndian.PutUint32(b[off:], v)
	}
}

func hgPutBe32(b []byte, off int, v uint32) {
	if off+4 <= len(b) {
		binary.BigEndian.PutUint32(b[off:], v)
	}
}

func hgPutU64Le(b []byte, off int, v uint64) {
	if off+8 <= len(b) {
		binary.LittleEndian.PutUint64(b[off:], v)
	}
}

func hgPutU64Be(b []byte, off int, v uint64) {
	if off+8 <= len(b) {
		binary.BigEndian.PutUint64(b[off:], v)
	}
}

func hgReadU64Le(b []byte, off int) uint64 {
	if off+8 > len(b) {
		return 0
	}
	return binary.LittleEndian.Uint64(b[off:])
}

// 8 位循环左移 4 位。
func hgRotl8(x byte) byte { return x<<4 | x>>4 }

// 8 位循环左移 3 位（xmxor 专用）。
func hgRotl8_3(x byte) byte { return x<<3 | x>>5 }

// 反转一个字节的 8 个位。
func hgReverseBits8(value byte) byte {
	var r byte
	for i := 0; i < 8; i++ {
		r = (r << 1) | ((value >> i) & 1)
	}
	return r
}

func hgXorBytes(a, b []byte) []byte {
	out := make([]byte, len(a))
	for i := range out {
		out[i] = a[i] ^ b[i%len(b)]
	}
	return out
}

func hgMd5(data []byte) []byte {
	sum := md5.Sum(data)
	return sum[:]
}

func hgMd5HexUpper(data []byte) string {
	return strings.ToUpper(hex.EncodeToString(hgMd5(data)))
}

func hgSM3Bytes(input []byte) []byte {
	sum := hongguoSM3(input)
	return sum[:]
}

func hgUnhexMust(text string) []byte {
	raw, err := hex.DecodeString(text)
	if err != nil {
		panic("hongguo pure-sign: invalid hex constant")
	}
	return raw
}

// ==================== protobuf 手写编码 ====================

// hgProtoField 对应 JS protoField 的 (tag, value, type) 三元组；
// kind 取值 "string" / "bytes" / "message" / "float" / "sint" / "int"。
type hgProtoField struct {
	tag   uint64
	value any
	kind  string
}

func hgVarint(value uint64) []byte {
	var out []byte
	for value > 127 {
		out = append(out, byte((value&127)|128))
		value >>= 7
	}
	return append(out, byte(value))
}

func hgZigzag(value int64) uint64 {
	if value < 0 {
		return uint64(-value)*2 - 1
	}
	return uint64(value) * 2
}

func hgProtoEncode(fields []hgProtoField) []byte {
	var out []byte
	for _, field := range fields {
		out = append(out, hgProtoFieldEncode(field)...)
	}
	return out
}

func hgProtoFieldEncode(field hgProtoField) []byte {
	tag, kind := field.tag, field.kind
	if kind == "" {
		kind = "string"
	}
	var body []byte
	var head []byte
	switch kind {
	case "bytes":
		value, _ := field.value.([]byte)
		if value == nil {
			return nil
		}
		body = value
		head = hgConcat(hgVarint(tag<<3|2), hgVarint(uint64(len(body))))
	case "message":
		value, _ := field.value.([]byte)
		if value == nil {
			return nil
		}
		body = value
		head = hgConcat(hgVarint(tag<<3|2), hgVarint(uint64(len(body))))
	case "string":
		text, _ := field.value.(string)
		if text == "" {
			return nil
		}
		body = []byte(text)
		head = hgConcat(hgVarint(tag<<3|2), hgVarint(uint64(len(body))))
	case "float":
		var block [4]byte
		switch value := field.value.(type) {
		case float64:
			binary.LittleEndian.PutUint32(block[:], math.Float32bits(float32(value)))
		case float32:
			binary.LittleEndian.PutUint32(block[:], math.Float32bits(float32(value)))
		}
		body = block[:]
		head = hgVarint(tag<<3 | 5)
	default: // "sint" / "int"
		var v int64
		switch value := field.value.(type) {
		case int64:
			v = value
		case int:
			v = int64(value)
		case uint64:
			v = int64(value)
		}
		if kind == "sint" {
			head = hgVarint(tag << 3)
			body = hgVarint(hgZigzag(v))
		} else {
			head = hgVarint(tag << 3)
			body = hgVarint(uint64(v))
		}
	}
	return hgConcat(head, body)
}

// ==================== hashF13 家族 ====================

// hgGetIv 按字节奇偶交替混合的 32 位状态机。
func hgGetIv(iv uint32, data []byte) uint32 {
	value := iv
	for i := 0; i < len(data); i++ {
		d := uint32(data[i])
		if i%2 == 0 {
			value = (value >> 4) ^ value ^ (value << 6) ^ d
		} else {
			value = ^((value >> 7) ^ value ^ (d | (value << 12)))
		}
	}
	return value
}

// hgSumMd5 取前 12 字节的固定轮混淆，末位或 4 再异或 0x1000000。
func hgSumMd5(data []byte) uint32 {
	check := uint32(0x20220420)
	for i := 0; i < 12; i++ {
		var temp uint32
		if i%2 == 0 {
			temp = (check >> 3) ^ check
		} else {
			temp = (check >> 5) ^ check
		}
		if i%2 == 0 {
			check = uint32(data[i]) ^ (check << 7)
		} else {
			check = uint32(data[i]) | (check << 11)
		}
		if i%2 != 0 {
			check = ^check
		}
		check = check ^ temp
	}
	return (check | 4) ^ 0x01000000
}

var hgBranch2SV = [...]uint32{
	0xa7aefe20, 0x7149f1d6, 0x47e4ca07, 0xe9b58f67, 0x93b924de, 0xc614d0f5, 0x38afe0ef, 0xb2bbad73,
	0xe24444c3, 0x9d3aec9b, 0xdf7b37e4, 0xd8b16d40, 0xf8ac31b8, 0x76b9a90b, 0x31d833ee, 0x953fce64,
	0x353595a4, 0x4609c13b, 0x36925008, 0x8c6d0925, 0x5df5c177, 0x1cfbf52b, 0x8a4fa7f0, 0x114ca35e,
	0x8193f984, 0x7a7a8733, 0x316ab4d5, 0x3c20cfc9, 0xa6d84453, 0x3a18500c, 0x798ec47a, 0x97a76b28,
	0x66c4ff96, 0x51716443, 0x0dd2fc3b, 0xb5696da7, 0xbbeb3ac5, 0x5c53d204, 0xd32608ce, 0x7279b9ec,
	0xf4188ecf, 0xf7d793db, 0x332cc491, 0xab76ae15, 0x9bebe727, 0x18a01384, 0x5be9f8a7, 0x5f90a754,
	0x39b663c0, 0x36673c83, 0x7c92f514, 0x9d7d94d7, 0xe2e8d9aa, 0x5f7e9ea9, 0x7abd4551, 0x569e05da,
	0x40a25632, 0x3df5a9a5, 0xbab37d80, 0x454286dc, 0x3f5d4e78, 0x03d7b75d, 0xb1fe4af7, 0xa5ab26a3,
}

var hgBranch2Orders = hgUnhexMust(
	"0f0704000908030a060b050d0e010c02" +
		"0f05080c0009020103070e060b0a0d04" +
		"060500070c000a04080f010b0d09020e" +
		"060b02050403080101070a000d0c090e" +
		"0d070e0f0b0208030c0509010004060a" +
		"0d0902060f0b0a040807000c0503010e" +
		"0c090f07060f030e020d0405010b0a00" +
		"0c050a090e0802040407030f01060b00" +
		"0b0f0408020a0700090d06010e03050c" +
		"0b060a0508020c03070f0e090d000104" +
		"0906080f050800040a0b030d01020c0e" +
		"090d0c0604070a03030f00080105020e" +
		"01000d0f090a0b0e0402080703060c05" +
		"01080a0c0f0905060b000304020e070d" +
		"04080f000c0f0e0d0a01060207090503" +
		"040205080d0b0a0606000e0f070c0903" +
		"0a08040f000b01060d0c0709030e0502" +
		"0a070b050f00020e0108030d0c060904" +
		"0d070f08050f06040b0a0e0c09000203" +
		"0d0c020704010b0e0e08060f09050003")

func hgMd5V3Step(kind int, a, b, c, d, m uint32, mValid bool, shift uint, constant uint32) uint32 {
	if !mValid {
		// JS 语义：m 越界读为 undefined，(a+f+m+constant) 整体变 NaN，
		// NaN|0 = 0，rotl(0) = 0，故本步结果恒为 b。
		return b
	}
	var f uint32
	switch kind {
	case 0:
		f = (b & c) | (^b & d)
	case 1:
		f = (b & d) | (c & ^d)
	case 2:
		f = b ^ c ^ d
	default:
		f = c ^ (b | ^d)
	}
	return b + bits.RotateLeft32(a+f+m+constant, int(shift&31))
}

// hgMd5SumV3 MD5 变体：固定轮常量表 + 消息编排表驱动的 64 轮压缩，返回 20 字节。
func hgMd5SumV3(message []byte, countV2 uint32, orders []byte, countV1 uint32) []byte {
	sv := make([]uint32, len(hgBranch2SV))
	for i := range sv {
		sv[i] = bits.RotateLeft32(hgBranch2SV[i], -int(countV1&31))
	}
	start := [4]uint32{
		bits.RotateLeft32(0x79e0f2fb, -int(countV2&31)),
		bits.RotateLeft32(0xc8b52570, -int(countV2&31)),
		bits.RotateLeft32(0xebc2f8cd, -int(countV2&31)),
		bits.RotateLeft32(0x7c104d93, -int(countV2&31)),
	}
	endCount := (countV2 + 6) & 255
	end := [4]uint32{
		bits.RotateLeft32(0x19be4866, -int(endCount&31)),
		bits.RotateLeft32(0xe85986b4, -int(endCount&31)),
		bits.RotateLeft32(0xe19b326e, -int(endCount&31)),
		bits.RotateLeft32(0x71d1d7d4, -int(endCount&31)),
	}
	var m [16]uint32
	for i := 0; i < 16; i++ {
		m[i] = hgReadLe32(message, i*4)
	}
	a, b, c, d := start[0], start[1], start[2], start[3]

	shifts := [4][16]uint{
		{7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22},
		{5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20},
		{4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23},
		{6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21},
	}
	for kind := 0; kind < 4; kind++ {
		offset := kind * 16
		for i := 0; i < 16; i++ {
			phase := i & 3
			// JS 语义：orders 越界读返回 undefined，参与 `| 0` 运算时按 0 处理。
			orderIndex := int(orders[offset+i] & 0xff)
			var mm uint32
			mmValid := orderIndex < len(m)
			if mmValid {
				mm = m[orderIndex]
			}
			cc := sv[offset+i]
			var next uint32
			switch phase {
			case 0:
				next = hgMd5V3Step(kind, a, b, c, d, mm, mmValid, shifts[kind][i], cc)
				a = next
			case 1:
				next = hgMd5V3Step(kind, d, a, b, c, mm, mmValid, shifts[kind][i], cc)
				d = next
			case 2:
				next = hgMd5V3Step(kind, c, d, a, b, mm, mmValid, shifts[kind][i], cc)
				c = next
			default:
				next = hgMd5V3Step(kind, b, c, d, a, mm, mmValid, shifts[kind][i], cc)
				b = next
			}
		}
	}
	ret := make([]byte, 16)
	hgPutLe32(ret, 0, (start[0]+a)^end[0])
	hgPutLe32(ret, 4, (start[1]+b)^end[1])
	hgPutLe32(ret, 8, (start[2]+c)^end[2])
	hgPutLe32(ret, 12, (start[3]+d)^end[3])
	return hgConcat(ret, hgLe32(hgSumMd5(ret)))
}

func hgBranch2F13(iv uint32, querySm3, bodyMd5, tsBytes []byte, khronos uint32) []byte {
	v := (iv & 13) * 86
	ivV0 := ((v >> 15) & 255) + ((v >> 8) & 255)
	n1 := [...]uint32{0x8980f29b, 0xeb549c7f, 0xb08726db, 0xd40cb5e6, 0xe8f559e4}[ivV0]
	countV1 := (n1 + khronos + 1) & 255
	countV2 := n1 + khronos
	shift := (countV2 + 5) & 7
	seed := []byte{0x84, 0x96, 0x77, 0x9d, 0xd4, 0x15, 0x0b, 0xf8}
	pad := make([]byte, 8)
	for i := 0; i < 8; i++ {
		pad[i] = byte((uint32(seed[i]) | (uint32(seed[i]) << 8)) >> shift)
	}
	input := hgConcat(querySm3, bodyMd5, tsBytes, pad, hgUnhexMust("a0010000"))
	orders := hgBranch2Orders[ivV0<<6 : (ivV0+1)<<6]
	return hgMd5SumV3(input, countV2, orders, countV1)
}

// hgHashF13 按 iv 低 4 位选分支（0 为主分支，1 不被服务端接受，2 为备用变体）。
func hgHashF13(querySm3, bodyMd5, tsBytes []byte, khronos uint32) []byte {
	iv := hgGetIv(hgGetIv(hgGetIv(0x20230928, querySm3), bodyMd5), tsBytes)
	low := iv & 15
	ivV0 := (low * 171) >> 9
	branch := low - ivV0*3
	if branch == 2 {
		return hgBranch2F13(iv, querySm3, bodyMd5, tsBytes, khronos)
	}
	if branch != 0 {
		return hgConcat(querySm3[:16], bodyMd5, hgLe32(hgSumMd5(hgConcat(querySm3, bodyMd5))))
	}

	ivV1List := [...]uint32{0xc4a78580, 0xb3c0fd39, 0xc58c5686, 0xc9aa3ba7, 0xf5a7adf2, 0x963c2ed1}
	ivV1 := ivV1List[ivV0]
	countV1 := (ivV1 + khronos + 1) & 255
	countV2 := ivV1 + khronos
	tt02 := [...]uint32{
		0xebb64faf, 0x07aadcc2, 0xcf3187bf, 0xe01138ff, 0x6d0bfcff, 0x5a30a3be, 0xb41ad638, 0x34180eb8,
		0xf233eb6f, 0xb1a584cc, 0xccc30dc7, 0x47d1db51, 0xd55653de, 0x70a84fa1, 0x57473c12, 0xf76f0288,
		0x2c077f0a, 0xda0dcad0, 0xfbb86f6c, 0xfdc4cf00, 0x688a020d, 0xe676c6a6, 0x8cd6338b, 0x1a3c8d0e,
		0xcce8b06b, 0x6ad0ed0b, 0xa0522717, 0xdc71ac83, 0x2285db71, 0xd5b4dda6, 0x736f8650, 0x6560306c,
		0x617ce2a6, 0xe423417e, 0x0a40e143, 0x544e4032, 0x88dffb2a, 0x716c1ae0, 0x4c467a88, 0x05b23bb3,
		0xe1d0b866, 0xbaa3dcb8, 0xae3374d3, 0xc3381a50, 0x1702f75b, 0xfe6da368, 0xf0b4cf48, 0x4e0ffbb8,
		0x72aad10d, 0x26c53a3d, 0xf2bce0f6, 0xb4557581, 0x4a257fdd, 0x8c3182a2, 0xab0b3b86, 0x3d5dfb14,
		0x4f103634, 0xd37b52d7, 0x444eff16, 0xeb0a33d1, 0x6ca86f6e, 0x0284ba7, 0x08387cfa, 0x5fb37586,
	}
	tt := make([]uint32, len(tt02))
	for i := range tt {
		tt[i] = bits.RotateLeft32(tt02[i], -int(countV1&31))
	}
	n0 := (countV2 + 2) & 7
	seed := []byte{0xfa, 0x45, 0x61, 0xd7}
	pad := make([]byte, len(seed))
	for i := range seed {
		pad[i] = byte((uint32(seed[i]) | (uint32(seed[i]) << 8)) >> n0)
	}
	data := hgConcat(querySm3, bodyMd5, tsBytes, pad, hgUnhexMust("00000000000001a0"))

	di := make([]uint32, len(data)/4+112+16)
	diLen := 0
	for i := 0; i+3 < len(data); i += 4 {
		di[diLen] = hgReadBe32(data, i)
		diLen++
	}
	di0 := di[0]
	for i := 0; i < 112; i++ {
		di1 := di[i+1]
		di14 := di[i+14]
		r1 := bits.RotateLeft32(di1, 14) ^ bits.RotateLeft32(di1, 25) ^ (di1 >> 3)
		r2 := bits.RotateLeft32(di14, 13) ^ bits.RotateLeft32(di14, 15) ^ (di14 >> 10)
		di[diLen] = di0 + di[i+9] + r1 + r2
		diLen++
	}

	initRaw := [...]uint32{0x7aba4fc8, 0x67166507, 0x6403fa00, 0x340f512f, 984304912, 3005047866, 2874125293, 2152413264}
	init := make([]uint32, 8)
	for i := range init {
		init[i] = bits.RotateLeft32(initRaw[i], -int(countV2&31))
	}
	chosenTable := [...][11]int{
		{101, 5, 7, 6, 3, 2, 1, 0, 5, 4, 3},
		{96, 0, 6, 7, 5, 3, 2, 1, 5, 4, 4},
		{96, 7, 6, 2, 1, 4, 0, 5, 4, 3, 5},
		{99, 3, 6, 2, 4, 5, 1, 0, 0, 7, 6},
		{96, 0, 5, 6, 7, 3, 1, 2, 5, 4, 4},
		{100, 2, 0, 3, 5, 4, 6, 7, 2, 1, 5},
	}
	chosen := chosenTable[ivV0]
	d := append([]uint32(nil), init...)
	for i := 0; i < chosen[0]; i++ {
		base := ivV1 + uint32(i)
		n0v := di[base&127]
		n1 := ((d[chosen[3]] ^ d[chosen[4]]) & d[chosen[1]]) ^ d[chosen[3]]
		n2 := bits.RotateLeft32(d[chosen[1]], 26) ^ bits.RotateLeft32(d[chosen[1]], 21) ^ bits.RotateLeft32(d[chosen[1]], 7)
		n4 := n0v + n1 + n2 + tt[base&63] + d[chosen[5]]
		n5 := bits.RotateLeft32(d[chosen[2]], 30) ^ bits.RotateLeft32(d[chosen[2]], 19) ^ bits.RotateLeft32(d[chosen[2]], 10)
		n6 := (d[chosen[2]] & d[chosen[6]]) | ((d[chosen[2]] | d[chosen[6]]) & d[chosen[7]])
		n7 := n5 + n6
		old := d[chosen[9]]
		// d.unshift(d.pop())：末元素移到队首（循环右移一格）。
		last := d[len(d)-1]
		copy(d[1:], d[:len(d)-1])
		d[0] = last
		d[chosen[10]] = n7 + n4
		d[chosen[8]] = old + n4
	}
	ret := make([]byte, 32)
	for i := 0; i < 8; i++ {
		hgPutBe32(ret, i*4, (d[i]+init[i]))
	}
	for i := 0; i < 16; i++ {
		ret[i] = ret[i] ^ ret[i+16]
	}
	return hgConcat(ret[:16], hgLe32(hgSumMd5(ret[:16])))
}

// hgBranchOf 与 hashF13 相同的分支计算；branch==1 时服务端不认，调用方应抖动 _rticket 避开。
func hgBranchOf(query string, body []byte, khronos uint32) int {
	bodyMd5 := hgMd5(body)
	if len(body) == 0 {
		bodyMd5 = make([]byte, 16)
	}
	q := hgSM3Bytes([]byte(query))
	iv := hgGetIv(hgGetIv(hgGetIv(0x20230928, q), bodyMd5), hgLe32(khronos))
	low := iv & 15
	return int(low - ((low*171)>>9)*3)
}

// ==================== x-gorgon ====================

// hgRc4Gorgon RC4 变体（KSA 只赋值不交换，PRGA 异或 s[(y+y)&255]）。
func hgRc4Gorgon(data, key []byte) []byte {
	var s [256]byte
	for i := 0; i < 256; i++ {
		s[i] = byte(i)
	}
	j := 0
	for i := 0; i < 256; i++ {
		j = (j + int(s[i]) + int(key[i%len(key)])) & 255
		s[i] = s[j]
	}
	out := make([]byte, len(data))
	i := 0
	j = 0
	for k := 0; k < len(data); k++ {
		i++
		x := s[i]
		j = (j + int(x)) & 255
		y := s[j]
		s[i] = y
		out[k] = data[k] ^ s[(int(y)+int(y))&255]
	}
	return out
}

func hgXGorgon(query string, body []byte, timestamp uint32, random uint32) string {
	q4 := hgMd5([]byte(query))[:4]
	var b4 []byte
	if len(body) > 0 {
		b4 = hgMd5(body)[:4]
	} else {
		b4 = make([]byte, 4)
	}
	input := hgConcat(q4, b4, make([]byte, 4), hgLe32(67503104), hgBe32(timestamp))
	key := []byte{0x4a, 0x40, 0x16, byte((random >> 8) & 255), 0x47, 0x6c, 0x01, byte(random & 255)}
	out := hgRc4Gorgon(input, key)
	for i := 0; i < len(out); i++ {
		value := hgRotl8(out[i])
		var next byte
		if i+1 < len(out) {
			next = out[i+1]
		} else {
			next = out[0]
		}
		out[i] = ^(hgReverseBits8(next^value) ^ 20)
	}
	return hex.EncodeToString(hgConcat(hgUnhexMust("8404"), []byte{byte(random & 255), byte((random >> 8) & 255), 0x40, 0x01}, out))
}

// ==================== AesV3（medusa 内置的 AES 变体） ====================

var hgSbox = func() []byte {
	raw, err := base64.StdEncoding.DecodeString(
		"+n0Ia5xZs0sEXznQOEqRmQBnpiCf9U2Ccybu3xhmgzOAAxn72f6uqqmwUsYL83klTni0NqxdGieeiNu9PGPsSRXBMB/cuFbUbM3KCUPINaPvHvSW0vwOcnuUhNHqRVpiAj/TEoE0K91+5ijypUYTATsh9mE3KSoN7Yyvv51cuyR2D3XkU4nhmI2xmmVwT1RMWKtub4sjxAcRDLrPoKSO2AU9FLLadMPX577Wf95IFj6FkKFVt3dCIsmGUC4X+WQxLJvxbRxEaOPpqJOXyzJX6+Vxaq3AzMfF/WAdoi1Hp+JRaV56zgpBtpWP97mH4DoGEIq1+FvV8LyS/3wvwugbQOwb2r26mJEMsiuDQTRn+wrYdrVGBVlhI3WQhyrjUBVMrLF5667llUcEaPCGPVGLD8qO5LlO8hKCvA7V9+8oJc9bXelqVQLhM76T5/WtnT45JKji+hdX0HoNCDDWuKON/QeaxB5uImSX0h2wv0VmP2zd2yeApxHcpsVS+MC2yFwAc2B7oBkTqsk1SEvTpM2fmfMQREBUfin0Bh+iq6EvPPavhWI2IX9e3yAas7Tm/3KEj2UmlFp36kN4x0rMLBRrxuh0U/zUHM4xcAMYjJY4MonxOl/X+alpt2M3WMI7w3HLnpIBigtNiJu7T21v4P6lSd5WFgntnMEt7oF92XzRLkJbTcGmXepE/UVOG6E/0YnhfS+q26utWcuxzpooyeD2cDlK1/8w9d28VzsRjbLuALbmGlp8+d7EzS6Au7lMpZ+ECMZvQmzwJ+eLOpxR+2chdUExp8ogQyq3v9l68rX4jCwjg0+PYKAEEzcU4wHFY2ZcdIHfWL1okD3SszT0GZMyKdZJrg1L2AeerB4tC0C4crp2EHGo5FYdSP7lwkeR2ocmnR+Ia8CYviUJlzOjhRZef9xuVOn3qcjow3fQgivsAmKKkg4+sA8F8/GWeDiGNhg8JM8KtFPMYWWkx5TVFX5t73kiNRJqjlIGVXtGZFCV4gzt0xcDopuZ6xz8r9Rzafpf9ywev8jh8592gHFIqpStZPuJxmDDMrNN0uBE3V+oscdoIzTJbRJ/t+sVvqnReJOgDJKk10fjisJwqyZBmnmn2BSFj8BvVtCMEbkuPOKdzw7eA11GPs04Qw8zWtkaZWwiO/wwpojqN6K0jY5RnNZA7vn4hPSul+nKCkVnVwQvg1zVxcSCtqORmB9KrJaBbssbCQivGJVJfVTt+hYxOtq4ZvWl8f4QAQZ0zGPffCgl9s6yT4vlvIdpu4YhBwA25wtQWZsc6GJYGWHyvSdeuh3mmUI9DSq13Fsp8C1MU3tqc04/df9LoTUXVXI5INOw/e8C7Hd+5CvbkMEFnnrUUmskEw==")
	if err != nil || len(raw) != 1024 {
		panic("hongguo pure-sign: invalid AesV3 sbox")
	}
	return raw
}()

// hgAesSrc 对齐 JS 语义：越界读返回 0。
func hgAesSrc(data []byte, idx int) byte {
	if idx < 0 || idx >= len(data) {
		return 0
	}
	return data[idx]
}

// hgAesPut 对齐 JS 语义：越界写静默忽略。
func hgAesPut(data []byte, idx int, value byte) {
	if idx >= 0 && idx < len(data) {
		data[idx] = value
	}
}

type hgAesV3 struct {
	wordSize uint32
	box      []byte
	con2     [4]int
	order    [16]int
	keys     [12][4]byte
}

func newHgAesV3(key []byte, khronos uint32) *hgAesV3 {
	wordSize := khronos & 3
	box := hgSbox[wordSize*256 : (wordSize+1)*256]
	con2Table := [4][4]int{{1, 0, 2, 3}, {2, 0, 3, 1}, {0, 1, 3, 2}, {1, 0, 2, 3}}
	orderTable := [4][16]int{
		{0, 9, 14, 11, 4, 13, 2, 7, 8, 1, 6, 15, 12, 5, 10, 3},
		{0, 9, 14, 15, 4, 13, 2, 7, 8, 1, 6, 3, 12, 5, 10, 11},
		{0, 9, 14, 7, 4, 13, 2, 11, 8, 1, 6, 3, 12, 5, 10, 15},
		{0, 9, 14, 11, 4, 13, 2, 7, 8, 1, 6, 15, 12, 5, 10, 3},
	}
	init := [4]uint32{0xca025ddc, 0x823dc546, 0xc9420583, 0xc298225f}[wordSize]
	initial := make([]byte, 16)
	for i := 0; i < 4; i++ {
		hgPutLe32(initial, i*4, init)
	}
	mk := hgXorBytes(initial, key)
	expanded := make([]byte, 48)
	copy(expanded, mk)
	rounds := uint32(8)
	for i := 4; i < 12; i++ {
		at := 4 * (i - 1)
		a, b, c, d := expanded[at], expanded[at+1], expanded[at+2], expanded[at+3]
		if i&3 == 0 {
			t := ((init >> (rounds & 24)) ^ uint32(box[b])) & 255
			b = box[c]
			c = box[d]
			d = box[a]
			a = byte(t)
		}
		rounds += 2
		expanded[at+4] = a ^ expanded[at-12]
		expanded[at+5] = b ^ expanded[at-11]
		expanded[at+6] = c ^ expanded[at-10]
		expanded[at+7] = d ^ expanded[at-9]
	}
	cipher := &hgAesV3{wordSize: wordSize, box: box, con2: con2Table[wordSize]}
	copy(cipher.order[:], orderTable[wordSize][:])
	for i := 0; i < 12; i++ {
		for j := 0; j < 4; j++ {
			cipher.keys[i][j] = expanded[i*4+j]
		}
	}
	return cipher
}

func (cipher *hgAesV3) matrix(bytes []byte) [4][4]byte {
	var rows [4][4]byte
	for i := 0; i < 4; i++ {
		for j := 0; j < 4; j++ {
			rows[i][j] = hgAesSrc(bytes, i*4+j)
		}
	}
	return rows
}

func (cipher *hgAesV3) flat(rows [4][4]byte) []byte {
	out := make([]byte, 16)
	for i := 0; i < 4; i++ {
		for j := 0; j < 4; j++ {
			out[i*4+j] = rows[i][j]
		}
	}
	return out
}

func (cipher *hgAesV3) aesXt(x byte) byte {
	out := x << 1
	if x&128 != 0 {
		out ^= 0x1b
	}
	return out
}

func (cipher *hgAesV3) mix(rows *[4][4]byte) {
	for i := 0; i < 4; i++ {
		t := rows[0][i] ^ rows[1][i] ^ rows[2][i] ^ rows[3][i]
		u := rows[0][i]
		rows[0][i] ^= t ^ cipher.aesXt(rows[0][i]^rows[1][i])
		rows[1][i] ^= t ^ cipher.aesXt(rows[1][i]^rows[2][i])
		rows[2][i] ^= t ^ cipher.aesXt(rows[2][i]^rows[3][i])
		rows[3][i] ^= t ^ cipher.aesXt(rows[3][i]^u)
	}
}

func (cipher *hgAesV3) add(rows *[4][4]byte, key [4][4]byte) {
	for i := 0; i < 4; i++ {
		for j := 0; j < 4; j++ {
			rows[i][j] ^= key[i][j]
		}
	}
}

func (cipher *hgAesV3) addCon(rows *[4][4]byte, ks [4][4]byte) {
	for i := 0; i < 4; i++ {
		for j := 0; j < 4; j++ {
			rows[i][j] ^= ks[i][cipher.con2[j]]
		}
	}
}

func (cipher *hgAesV3) sub(rows *[4][4]byte) {
	for i := 0; i < 4; i++ {
		for j := 0; j < 4; j++ {
			rows[i][j] = cipher.box[rows[i][j]]
		}
	}
	var old [4][4]byte
	for i := 0; i < 4; i++ {
		old[i] = rows[i]
	}
	for i := 0; i < 4; i++ {
		rows[i] = old[cipher.con2[i]]
	}
}

func (cipher *hgAesV3) shift(rows *[4][4]byte) {
	b := cipher.flat(*rows)
	for i := 0; i < 16; i++ {
		rows[i/4][i%4] = b[cipher.order[i]]
	}
}

func (cipher *hgAesV3) shiftCon(rows *[4][4]byte) {
	var old [4][4]byte
	for i := 0; i < 4; i++ {
		old[i] = rows[i]
	}
	for i := 0; i < 4; i++ {
		for j := 0; j < 4; j++ {
			rows[i][j] = old[i][cipher.con2[j]]
		}
	}
}

func (cipher *hgAesV3) subKeys(from int) [4][4]byte {
	var out [4][4]byte
	for i := 0; i < 4; i++ {
		out[i] = cipher.keys[from+i]
	}
	return out
}

func (cipher *hgAesV3) block(value []byte) []byte {
	rows := cipher.matrix(value)
	cipher.addCon(&rows, cipher.subKeys(0))
	for i := 1; i < 3; i++ {
		cipher.sub(&rows)
		cipher.shift(&rows)
		if i == 1 {
			cipher.shiftCon(&rows)
			cipher.mix(&rows)
		}
		cipher.addCon(&rows, cipher.subKeys(i*4))
	}
	cipher.add(&rows, cipher.subKeys(4))
	return cipher.flat(rows)
}

// encrypt 明文具化到 32 字节 -> CBC 两轮 -> 按 key 逐位回填源数据，末尾缀 key 末字节。
func (cipher *hgAesV3) encrypt(data, iv []byte) []byte {
	plaintext := make([]byte, 32)
	for i := 0; i < 31; i++ {
		at := i * 8
		n0 := (hgAesSrc(data, at) >> 4) & 2
		n1 := n0 | (hgAesSrc(data, at+1) & 64)
		n2 := n1 | ((hgAesSrc(data, at+2) >> 2) & 1)
		n3 := n2 | ((hgAesSrc(data, at+3) << 3) & 128)
		n4 := n3 | ((hgAesSrc(data, at+4) >> 1) & 4)
		n5 := n4 | ((hgAesSrc(data, at+5) << 3) & 16)
		n6 := n5 | ((hgAesSrc(data, at+6) << 5) & 32)
		plaintext[i] = n6 | ((hgAesSrc(data, at+7) >> 4) & 8)
	}
	plaintext[31] = 1
	blocks := make([]byte, 0, 32)
	previous := append([]byte(nil), iv...)
	for i := 0; i < len(plaintext); i += 16 {
		value := cipher.block(hgXorBytes(plaintext[i:i+16], previous))
		blocks = append(blocks, value...)
		previous = value
	}
	out := append([]byte(nil), data...)
	for i := 0; i < 31; i++ {
		at := i * 8
		k := blocks[i]
		hgAesPut(out, at, (hgAesSrc(out, at)&0xdf)|((k<<4)&32))
		hgAesPut(out, at+1, (hgAesSrc(out, at+1)&0xbf)|(k&64))
		hgAesPut(out, at+2, (hgAesSrc(out, at+2)&0xfb)|((k<<2)&4))
		hgAesPut(out, at+3, (hgAesSrc(out, at+3)&0xef)|((k>>3)&16))
		hgAesPut(out, at+4, (hgAesSrc(out, at+4)&0xf7)|((k+k)&8))
		hgAesPut(out, at+5, (hgAesSrc(out, at+5)&0xfd)|((k>>3)&2))
		hgAesPut(out, at+6, (hgAesSrc(out, at+6)&0xfe)|((k>>5)&1))
		hgAesPut(out, at+7, (hgAesSrc(out, at+7)&0x7f)|((k<<4)&128))
	}
	return hgConcat(blocks[len(blocks)-1:], out)
}

// ==================== xmxor / keyHash / medusa / helios ====================

// hgXmxor 按 key 表逐字节混淆 + 三段尾部修正。
func hgXmxor(data, key []byte) []byte {
	encoded := make([]byte, len(data))
	for i := 0; i < len(data); i++ {
		at := (i * 4) & 28
		d0 := uint32(key[at])
		d1 := uint32(key[at+1])
		d2 := uint32(hgRotl8(data[i])) + d0
		d2 = (^d2) ^ d1
		d2 = uint32(hgRotl8_3(byte(d2)))
		d2 = (d2 + d1) & 255
		d2 = (d2 ^ d0) & 255
		encoded[len(data)-i-1] = ^byte(d2)
	}
	last := encoded[len(encoded)-1] ^ encoded[len(encoded)-2]
	first := encoded[0]
	encoded[0] = (^last) + first
	encoded[1] = ((encoded[0] ^ encoded[len(encoded)-1] ^ 254) + encoded[1])
	encoded[2] = encoded[2] + (((last - first) ^ hgRotl8_3(encoded[1])) ^ 2)
	for i := 0; i < len(encoded)-4; i++ {
		temp := hgRotl8_3(encoded[i+2]) ^ encoded[i+1] ^ byte(i+3)
		encoded[i+3] = (^temp) + encoded[i+3]
	}
	encoded[len(encoded)-1] = encoded[len(encoded)-1] ^ encoded[len(encoded)-2]
	sum := 0
	for i := 0; i < len(encoded)-1; i++ {
		sum += int(encoded[i+1])
	}
	encoded[0] = (encoded[0] ^ encoded[1]) + byte(sum)
	return encoded
}

// hgKeyHash signKey || le32(random) || signKey 的 SM3，附一个由 random 派生的 4 字节种子。
func hgKeyHash(signKey []byte, random uint32) ([]byte, []byte) {
	hash := hgSM3Bytes(hgConcat(signKey, hgLe32(random), signKey))
	d1 := (random >> 16) & 255
	d2 := ((((d1 << 11) | (random >> 24)) ^ (d1 >> 5) ^ d1))
	d2 = ^d2
	return hash, hgLe32(d2)
}

var (
	hgMedusaSignKey  = hgUnhexMust("8ebdfa3806ecc5cee79423e6029ed82540bc2218bb7eaef71cb691f7aa8aa2f5")
	hgMedusaAESKey   = hgUnhexMust("f1593376766ea98d34f31b057a9d5be4")
	hgMedusaAESIV    = hgUnhexMust("1fe109a4125283f418de9e051a969e12")
	hgMedusaMagic16  = hgUnhexMust("f7e85ffad7d7dc3bd62ac87057cf6118")
	hgMedusaMagic8   = hgUnhexMust("4001000000000000")
	hgMedusaVersion  = hgUnhexMust("03000000f7e85ffad7d7dc3bd62ac87057cf6118")
	hgProcessNonce   = func() string {
		raw := make([]byte, 18)
		if _, err := rand.Read(raw); err != nil {
			panic("hongguo pure-sign: process nonce")
		}
		return base64.RawURLEncoding.EncodeToString(raw)
	}()
	hgProcessStarted = uint64(hgNowUnixMilli())
)

// hgDeviceProto 设备信息 protobuf。字段 30-36 为固定设备值，不跟随 query 参数。
func hgDeviceProto(deviceId, version string) []byte {
	return hgProtoEncode([]hgProtoField{
		{1, int64(1), "sint"}, {2, int64(2), "sint"}, {3, "8662", ""}, {4, deviceId, ""},
		{5, hgProcessNonce, ""}, {6, "!noperm!", ""}, {7, int64(-888888), "sint"}, {8, int64(-888888), "sint"},
		{9, int64(3), "sint"}, {10, int64(-888888), "sint"}, {11, "!notset!", ""},
		{12, "Asia/Shanghai,8", ""}, {13, "zh_CN", ""}, {14, int64(4), "sint"},
		{16, float64(0), "float"}, {17, float64(0), "float"}, {18, float64(0), "float"}, {19, float64(0), "float"},
		{20, float64(0), "float"}, {21, float64(0), "float"}, {22, "16", ""}, {23, int64(41), "sint"},
		{24, int64(36), "sint"}, {25, int64(hgProcessStarted), "sint"}, {26, int64(hgProcessStarted), "sint"},
		{27, int64(hgProcessStarted), "sint"}, {28, int64(hgProcessStarted), "sint"}, {29, int64(-1), "sint"},
		{30, "25053RT47C", ""}, {31, "Redmi", ""}, {32, "25053RT47C", ""}, {33, "25053RT47C", ""},
		{34, "Xiaomi", ""}, {35, "Redmi", ""}, {36, "Redmi", ""}, {38, int64(31), "sint"},
	})
}

// hgBuildMedusa 构造 x-medusa。
func hgBuildMedusa(query string, body []byte, khronos uint32, deviceId, version string) string {
	bodyMd5 := hgMd5(body)
	if len(body) == 0 {
		bodyMd5 = make([]byte, 16)
	}
	querySm3 := hgSM3Bytes([]byte(query))
	ts := hgLe32(khronos)
	queryBodyTs := hgHashF13(querySm3, bodyMd5, ts, khronos)

	messageRand := make([]byte, 4)
	if _, err := rand.Read(messageRand); err != nil {
		panic("hongguo pure-sign: message rand")
	}
	messageRandU := binary.LittleEndian.Uint32(messageRand)
	envLaunch := uint32(100 + hgRndInt(21))
	envPid := uint32(10001 + hgRndInt(2000))
	env := hgProtoEncode([]hgProtoField{
		{1, int64(envLaunch), "sint"}, {2, int64(146331399), "sint"}, {3, int64(146331396), "sint"},
		{5, int64(7), "sint"}, {6, "v04.06.04.03-bugfix", ""}, {7, int64(envPid), "sint"},
		{12, hgDeviceProto(deviceId, version), "message"},
		{13, hgProtoEncode([]hgProtoField{
			{1, int64(hgNowUnix() ), "sint"},
			{2, int64(-2), "sint"}, {4, int64(200), "sint"},
		}), "message"},
		{14, version, ""},
	})
	queryHash := hgSM3Bytes(hgConcat([]byte(query), bodyMd5, []byte("none")))

	nested := hgProtoEncode([]hgProtoField{
		{1, int64(111), "sint"}, {2, int64(10), "sint"}, {3, int64(694367), "sint"}, {5, int64(586952199), "sint"},
	})
	message := hgProtoEncode([]hgProtoField{
		{1, hgMedusaMagic16, "bytes"}, {2, int64(3), "sint"}, {3, int64(messageRandU), "sint"},
		{4, "8662", ""}, {5, deviceId, ""}, {6, "1588093228", ""}, {7, version, ""},
		{8, "v04.06.04-ml-android", ""}, {9, int64(67503104), "sint"},
		{10, hgMedusaMagic8, "bytes"}, {12, int64(khronos), "sint"},
		{13, queryBodyTs, "bytes"}, {14, querySm3[:6], "bytes"},
		{15, nested, "message"}, {16, hgProcessNonce, ""}, {17, int64(khronos), "sint"},
		{19, queryHash, "bytes"}, {20, "none", ""}, {21, int64(312), "sint"},
		{23, env, "message"},
		{24, `{"cmr":16777216,"cmr2":16777216,"un_h":1879194040,"vpn":0,"kd":0,"fkd":3672518972,"pd":-1872573247,"dyn":"","do":0,"tk":true}`, ""},
	})

	random := hgRndInt32()
	hash, seed := hgKeyHash(hgMedusaSignKey, random)
	transformed := hgXmxor(message, hash)
	transformed = hgConcat(hgMedusaMagic8, transformed)
	// 整体逆序。
	for i, j := 0, len(transformed)-1; i < j; i, j = i+1, j-1 {
		transformed[i], transformed[j] = transformed[j], transformed[i]
	}
	for i := 0; i < len(transformed); i++ {
		transformed[i] = transformed[i] ^ seed[(^i)&3]
	}
	check := (((uint32(querySm3[0]) & 63) << 14) | 0x18000001 | ((uint32(queryBodyTs[0]) & 63) << 8))
	xmRand := hgRndInt32()
	packed := hgConcat([]byte{0x35}, hgLe32(xmRand), hgLe32(check), transformed,
		[]byte{byte((random >> 16) & 255), byte((random >> 24) & 255)})
	encrypted := newHgAesV3(hgMedusaAESKey, khronos).encrypt(packed, hgMedusaAESIV)
	prefix := make([]byte, 20)
	for i := 0; i < 20; i += 4 {
		hgPutLe32(prefix, i, hgReadLe32(hgMedusaVersion, i)^khronos)
	}
	return base64.StdEncoding.EncodeToString(hgConcat(prefix,
		[]byte{byte(random & 255), byte((random >> 8) & 255), 0, 1}, encrypted))
}

// hgHelios md5 ASCII 化 -> 64 位字表 -> 34 轮扩展 -> 分组类 Feistel。
func hgHelios(khronos uint32, random uint32) string {
	digest := hgMd5(hgConcat(hgLe32(random), []byte("8662")))
	ascii := []byte(hex.EncodeToString(digest))
	words := [4]uint64{hgReadU64Le(ascii, 0), hgReadU64Le(ascii, 8), hgReadU64Le(ascii, 16), hgReadU64Le(ascii, 24)}

	queue := []uint64{words[2], words[3]}
	b0 := words[0]
	b8 := words[1]
	table := make([]uint64, 35)
	table[0] = words[0]
	for i := 0; i < 34; i++ {
		x8 := bits.RotateLeft64(b8, -8) + b0
		x8 = x8 ^ uint64(i)
		queue = append(queue, x8)
		x8 = x8 ^ bits.RotateLeft64(b0, -61)
		table[i+1] = x8
		b0 = x8
		b8 = queue[0]
		queue = queue[1:]
	}
	text := strconv.FormatUint(uint64(khronos), 10) + "-1588093228-8662"
	tb := []byte(text)
	padLen := (len(tb) + 1 + 15) / 16 * 16
	pad := make([]byte, padLen)
	for i := range pad {
		pad[i] = byte(16 - (len(tb) % 16))
	}
	copy(pad, tb)

	var output []byte
	for at := 0; at < len(pad); at += 16 {
		a := hgReadU64Le(pad, at)
		b := hgReadU64Le(pad, at+8)
		for i := 0; i < 34; i++ {
			b = table[i] ^ (a + bits.RotateLeft64(b, -8))
			a = b ^ bits.RotateLeft64(a, -61)
		}
		block := make([]byte, 16)
		hgPutU64Le(block, 0, a)
		hgPutU64Le(block, 8, b)
		output = append(output, block...)
	}
	return base64.StdEncoding.EncodeToString(hgConcat(hgLe32(random), output))
}

// ==================== 入口 ====================

// hgRndInt 对应 Java RND.nextInt(n)：返回 [0, n) 的整数。
func hgRndInt(n int) int {
	limit := uint32(n)
	if limit == 0 {
		return 0
	}
	raw := make([]byte, 4)
	if _, err := rand.Read(raw); err != nil {
		panic("hongguo pure-sign: rnd int")
	}
	return int(binary.BigEndian.Uint32(raw) % limit)
}

// hgRndInt32 对应 Java RND.nextInt()：返回 32 位整数。
func hgRndInt32() uint32 {
	raw := make([]byte, 4)
	if _, err := rand.Read(raw); err != nil {
		panic("hongguo pure-sign: rnd int32")
	}
	return binary.BigEndian.Uint32(raw)
}

// hgNowUnixMilli / hgNowUnix 包级可被测试替身；默认取真实时钟。
var (
	hgClockNow     = time.Now
	hgNowUnixMilli = func() int64 { return hgClockNow().UnixMilli() }
	hgNowUnix      = func() int64 { return hgClockNow().Unix() }
)

// hongguoPureSign 计算一组签名头（六个），url 必须与最终请求完全一致。
func hongguoPureSign(url string, body []byte, khronos uint32) map[string]string {
	gorgonRandom := uint32(hgRndInt(65536))
	query := ""
	if i := strings.Index(url, "?"); i >= 0 {
		query = url[i+1:]
	}
	out := map[string]string{}
	out["x-gorgon"] = hgXGorgon(query, body, khronos, gorgonRandom)
	out["x-khronos"] = strconv.FormatUint(uint64(khronos), 10)
	out["x-ladon"] = base64.StdEncoding.EncodeToString(hgBe32(khronos))
	out["x-argus"] = base64.StdEncoding.EncodeToString(hgLe32(khronos))
	out["x-helios"] = hgHelios(khronos, hgRndInt32())
	out["x-medusa"] = hgBuildMedusa(query, body, khronos,
		hgParamOf(query, "device_id", "0"),
		hgParamOf(query, "version_name", "7.1.3.32"))
	return out
}

// hgParamOf 从查询串中取指定键的值（未编码），取不到返回 fallback。
func hgParamOf(query, key, fallback string) string {
	for _, kv := range strings.Split(query, "&") {
		eq := strings.Index(kv, "=")
		if eq <= 0 {
			continue
		}
		if kv[:eq] == key {
			if value := kv[eq+1:]; len(value) > 0 {
				return value
			}
		}
	}
	return fallback
}
