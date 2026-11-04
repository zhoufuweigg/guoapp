package core

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/sha512"
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"
)

func TestHongguoPyEncode(t *testing.T) {
	cases := []struct{ in, want string }{
		{"1280*2772", "1280%2A2772"},
		{"a!b'c(d)e", "a%21b%27c%28d%29e"},
		{"novelread", "novelread"},
		{"arm64-v8a", "arm64-v8a"},
		{"update_64", "update_64"},
	}
	for _, c := range cases {
		if got := hongguoPyEncode(c.in); got != c.want {
			t.Errorf("hongguoPyEncode(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestHongguoCheckedURL(t *testing.T) {
	cases := []struct {
		url     string
		domains []string
		want    bool
	}{
		{"https://v5-reading-video-c.qznovelvod.com/abc", hongguoVodDomains, true},
		{"https://qznovelvod.com/abc", hongguoVodDomains, true},
		{"https://api5-normal-sinfonlineb.fqnovel.com/x", hongguoAPIDomains, true},
		{"https://snssdk.com/x", hongguoAPIDomains, true},
		{"http://v5.qznovelvod.com/abc", hongguoVodDomains, false},
		{"https://evil.com/qznovelvod.com", hongguoVodDomains, false},
		{"https://notqznovelvod.com/abc", hongguoVodDomains, false},
		{"https://qznovelvod.com:8443/abc", hongguoVodDomains, false},
		{"https://user@qznovelvod.com/abc", hongguoVodDomains, false},
	}
	for _, c := range cases {
		if got := hongguoCheckedURL(c.url, c.domains); got != c.want {
			t.Errorf("hongguoCheckedURL(%q) = %v, want %v", c.url, got, c.want)
		}
	}
}

func TestHongguoParseFallback(t *testing.T) {
	cases := []struct {
		value any
		want  string
	}{
		{"https://api.fqnovel.com/x", "https://api.fqnovel.com/x"},
		{[]any{"https://api.fqnovel.com/x"}, "https://api.fqnovel.com/x"},
		{map[string]any{"fallback_api": "https://api.fqnovel.com/x"}, "https://api.fqnovel.com/x"},
		{`{"fallback_api":"https://api.fqnovel.com/x"}`, "https://api.fqnovel.com/x"},
		{"", ""},
		{nil, ""},
	}
	for _, c := range cases {
		if got := hongguoParseFallback(c.value); got != c.want {
			t.Errorf("hongguoParseFallback(%v) = %q, want %q", c.value, got, c.want)
		}
	}
}

// hongguoEncryptSpadeURLForTest 加密端：与 hongguoDecryptSpadeURL 互为逆运算。
func hongguoEncryptSpadeURLForTest(t *testing.T, mediaURL string, seed []byte) string {
	t.Helper()
	plain := []byte(mediaURL)
	pad := 16 - len(plain)%16
	if pad == 0 {
		pad = 16
	}
	for i := 0; i < pad; i++ {
		plain = append(plain, byte(pad))
	}
	h1 := sha512.Sum512(seed)
	h2 := sha512.Sum512(append(h1[:], hongguoURLConstants...))
	block, err := aes.NewCipher(h2[:16])
	if err != nil {
		t.Fatal(err)
	}
	ciphertext := make([]byte, len(plain))
	cipher.NewCBCEncrypter(block, h2[16:32]).CryptBlocks(ciphertext, plain)
	raw := append([]byte{0xa8, 0x00, 0x01, 0x00}, ciphertext...)
	return base64.StdEncoding.EncodeToString(raw)
}

func TestHongguoDecryptSpadeURLRoundTrip(t *testing.T) {
	seed := []byte("0123456789abcdef0123456789abcdef")
	mediaURL := "https://v5-reading-video-c.qznovelvod.com/248054a3017c0322021733441010e592/6ad97bf2/video/tos/cn/tos-cn-v-6fcc8e/os?bcv=1"
	encoded := hongguoEncryptSpadeURLForTest(t, mediaURL, seed)
	decoded, err := hongguoDecryptSpadeURL(encoded, seed)
	if err != nil {
		t.Fatalf("解密失败: %v", err)
	}
	if decoded != mediaURL {
		t.Errorf("往返不一致:\n got=%q\nwant=%q", decoded, mediaURL)
	}
}

func TestHongguoDecryptSpadeURLRejectsBadHeader(t *testing.T) {
	raw := []byte{0xa9, 0x00, 0x01, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
	if _, err := hongguoDecryptSpadeURL(base64.StdEncoding.EncodeToString(raw), []byte("seed")); err == nil {
		t.Error("期望拒绝错误的密文头")
	}
}

func TestSelectHongguoFallbackMediaPrefersH264(t *testing.T) {
	// 构造 video_info.data：HEVC 高码率在上，H.264 在下——应按 codec 优先选 H.264。
	info := map[string]any{
		"video_list": map[string]any{
			"hevc_1080p": map[string]any{
				"main_url":   "https://v5-reading-video-c.qznovelvod.com/hevc/1080p",
				"codec_type": "hevc",
				"definition": "1080p",
				"vwidth":     "1920", "vheight": "1080",
			},
			"h264_720p": map[string]any{
				"main_url":   "https://v5-reading-video-c.qznovelvod.com/h264/720p",
				"codec_type": "h264",
				"definition": "720p",
				"vwidth":     "1280", "vheight": "720",
			},
			"bytevc2": map[string]any{
				"main_url":   "https://v5-reading-video-c.qznovelvod.com/bytevc2",
				"codec_type": "bytevc2",
				"definition": "1080p",
			},
		},
	}
	media, err := selectHongguoFallbackMedia(info)
	if err != nil {
		t.Fatalf("选流失败: %v", err)
	}
	if !strings.Contains(media.URL, "/h264/720p") {
		t.Errorf("期望选 H.264，实际 %q", media.URL)
	}
	if media.Quality != 720 {
		t.Errorf("期望清晰度 720，实际 %d", media.Quality)
	}
}

func TestSelectHongguoFallbackMediaDecryptsAndSkipsBadCandidates(t *testing.T) {
	seed := []byte("0123456789abcdef0123456789abcdef")
	encrypted := hongguoEncryptSpadeURLForTest(t, "https://v26-reading-videocdn302.qznovelvod.com/enc/1080p", seed)
	info := map[string]any{
		"key_seed": base64.StdEncoding.EncodeToString(seed),
		"video_list": map[string]any{
			"1080p": map[string]any{
				// main_url 是密文，backup 是明文且在白名单外——都应跳过后由密文解密成功。
				"main_url":       encrypted,
				"backup_url":     "https://evil.com/plain",
				"backup_url_list": []any{"https://v5-reading-video-a.qznovelvod.com/plain/720p"},
				"codec_type":      "h264",
				"definition":      "1080p",
			},
		},
	}
	media, err := selectHongguoFallbackMedia(info)
	if err != nil {
		t.Fatalf("选流失败: %v", err)
	}
	if media.URL != "https://v26-reading-videocdn302.qznovelvod.com/enc/1080p" {
		t.Errorf("期望解密后的密文候选优先，实际 %q", media.URL)
	}
}

func TestHongguoFallbackRowSpadeKeyRejection(t *testing.T) {
	// spade_a 解不出合法 key 的候选应被跳过，而不是误报成功。
	info := map[string]any{
		"video_list": map[string]any{
			"bad": map[string]any{
				"main_url":  "https://v5-reading-video-c.qznovelvod.com/bad",
				"codec_type": "h264",
				"definition": "1080p",
				"spade_a":   "###not-base64###",
			},
		},
	}
	if _, err := selectHongguoFallbackMedia(info); err == nil {
		t.Error("期望因密钥无效而失败")
	}
}

func TestHongguoDeviceQueryShape(t *testing.T) {
	query := hongguoDeviceQuery(1770000000, 1770000000123, "1000000000000001", "1000000000000002")
	fields := map[string]string{}
	for _, pair := range strings.Split(query, "&") {
		eq := strings.Index(pair, "=")
		if eq > 0 {
			fields[pair[:eq]] = pair[eq+1:]
		}
	}
	want := map[string]string{
		"aid": "8662", "app_name": "novelread", "version_code": "71332",
		"version_name": "7.1.3.32", "device_platform": "android", "os": "android",
		"resolution": "1280%2A2772", "host_abi": "arm64-v8a", "video_platform": "",
		"ts": "1770000000", "_rticket": "1770000000123",
		"iid": "1000000000000001", "device_id": "1000000000000002",
	}
	for key, value := range want {
		if key == "video_platform" {
			continue
		}
		if fields[key] != value {
			t.Errorf("query[%q] = %q, want %q", key, fields[key], value)
		}
	}
	if strings.Contains(query, "video_platform") {
		t.Error("query 不应包含 video_platform（它在 body 里）")
	}
}

func TestHongguoMultiPayloadShape(t *testing.T) {
	body, err := json.Marshal(hongguoMultiPayload{
		BizParam:        hongguoMultiBizParam{VideoPlatform: 1024, NeedAllVideoDefinition: true, DeviceLevel: 3},
		MixedVideoIDMap: map[string][]string{"1004": {"7697855411688311833"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	text := string(body)
	if !strings.Contains(text, `"video_platform":1024`) {
		t.Errorf("body 缺少 video_platform=1024: %s", text)
	}
	if !strings.Contains(text, `"mixed_video_id_map":{"1004":["7697855411688311833"]}`) {
		t.Errorf("body mixed_video_id_map 形状不对: %s", text)
	}
}
