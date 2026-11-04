package core

import (
	"crypto/md5"
	"encoding/hex"
	"testing"
)

// 临时对拍：与 Node 参考实现（pure-sign.js）对固定输入逐项比对。
func TestDiagHongguoPureSignParity(t *testing.T) {
	query := "aid=8662&ts=1770000000&_rticket=1770000000123"
	body := []byte(`{"biz_param":{"video_platform":1024},"mixed_video_id_map":{"1004":["7697855411688311833"]}}`)
	khronos := uint32(1770000000)
	bodyMd5 := hgMd5(body)
	querySm3 := hgSM3Bytes([]byte(query))
	tsBytes := hgLe32(khronos)

	cases := []struct {
		name   string
		expect string
		actual string
	}{
		{"gorgon", "84043412400180a1da45842510fa1364e71df6105a76da2a6dfb", hgXGorgon(query, body, khronos, 0x1234)},
		{"hashF13", "426da58b65b5c21c245583748133315cceb796a7", hex.EncodeToString(hgHashF13(querySm3, bodyMd5, tsBytes, khronos))},
		{"helios", "8N68mm9GDGuWtWiPo8ccx97W9ZCrsjG7Nnep6e4KlrQ6lDSs", hgHelios(khronos, 0x9abcdef0)},
		{"ladon", "aYAOgA==", hongguoPureSign("https://x/?"+query, body, khronos)["x-ladon"]},
		{"argus", "gA6AaQ==", hongguoPureSign("https://x/?"+query, body, khronos)["x-argus"]},
		{"khronos", "1770000000", hongguoPureSign("https://x/?"+query, body, khronos)["x-khronos"]},
		{"getiv", "873850e0", hex.EncodeToString(func() []byte { v := hgGetIv(0x20230928, querySm3); return hgLe32(v) }())},
		{"summd5", "cdf79970", hex.EncodeToString(func() []byte { v := hgSumMd5(querySm3); return hgLe32(v) }())},
		{"branch", "2", itoa(hgBranchOf(query, body, khronos))},
		{"xmxor", "803dfde17b04ab523e97860e6b5fddfe2917ef3f67aa4cd9cd0bc6ac92beda591f6133dc", hex.EncodeToString(hgXmxor([]byte("0123456789abcdefghijklmnopqrstuvwxyz"), []byte("0123456789abcdef0123456789abcdef")))},
		{"aesv3", "d5307136333c3736b738796562636465e64768697a636e6cee4f307562737674765778797a", hex.EncodeToString(newHgAesV3(hgMedusaAESKey, khronos).encrypt([]byte("0123456789abcdefghijklmnopqrstuvwxyz"), hgMedusaAESIV))},
		{"md5v3", "c78e542841cca72c711192992195a6e3fc29d3a2", hex.EncodeToString(hgMd5SumV3(hgRange64(), khronos, hgRange64(), 0x33))},
		{"rc4", "a8d4fbffaa35c5376ddbb8a573a87475c6facabd3fd7d5dbda63bfd9b0c5acc7c0f9c959885f5bcbfe85d0e1d09f01cfcaf208f99899ca18c4f3e24190919efd", hex.EncodeToString(hgRc4Gorgon(hgRange64(), []byte("0123456789abcdef0123456789abcdef")))},
	}
	failed := 0
	for _, c := range cases {
		if c.expect != c.actual {
			t.Errorf("%s 不一致:\n  expect=%s\n  actual=%s", c.name, c.expect, c.actual)
			failed++
		}
	}
	t.Logf("对拍完成：%d/%d 一致", len(cases)-failed, len(cases))
}

func hgRange64() []byte {
	out := make([]byte, 64)
	for i := range out {
		out[i] = byte(i)
	}
	return out
}

func itoa(v int) string {
	if v == 0 {
		return "0"
	}
	negative := v < 0
	if negative {
		v = -v
	}
	var digits []byte
	for v > 0 {
		digits = append([]byte{byte('0' + v%10)}, digits...)
		v /= 10
	}
	if negative {
		return "-" + string(digits)
	}
	return string(digits)
}

var _ = md5.Sum
