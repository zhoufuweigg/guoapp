package core

import (
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"
)

// hongguoVideoModel 兼容三种下发结构：
// 1) data.video_model 为对象；
// 2) data.video_model 为 base64 字符串（解码后是 JSON）；
// 3) video_list 直接平铺在 data 上（含 video_model 只带时长、无列表的情况）。
func hongguoVideoModel(data map[string]any) (map[string]any, error) {
	model, _ := data["video_model"].(map[string]any)
	if encoded, ok := data["video_model"].(string); ok && encoded != "" {
		// 服务端会以两种形式下发 video_model：base64 编码的 JSON，或明文 JSON 字符串
		// （实测 {"status":10,"message":"success","video_list":[...]} 为正常下发）。
		// 明文 JSON 以 { 或 [ 开头，直接解析；其余先尝试 base64 解码，两者都失败才报错。
		text := encoded
		trimmed := strings.TrimSpace(text)
		if !strings.HasPrefix(trimmed, "{") && !strings.HasPrefix(trimmed, "[") {
			if decoded, err := decodeHongguoBase64(encoded); err == nil && len(decoded) > 0 {
				text = string(decoded)
			}
		}
		decoder := json.NewDecoder(strings.NewReader(text))
		decoder.UseNumber()
		if err := decoder.Decode(&model); err != nil {
			return nil, fmt.Errorf("红果 App 播放信息格式异常（%s）: %w", hongguoClipText(text, 24), err)
		}
	}
	if len(anyList(model["video_list"])) == 0 {
		if rows := anyList(data["video_list"]); len(rows) > 0 {
			merged := make(map[string]any, len(model)+3)
			for key, value := range model {
				merged[key] = value
			}
			merged["video_list"] = data["video_list"]
			if _, ok := merged["video_duration"]; !ok {
				merged["video_duration"] = data["video_duration"]
			}
			if _, ok := merged["duration"]; !ok {
				merged["duration"] = data["duration"]
			}
			model = merged
		}
	}
	return model, nil
}

func hongguoClipText(value string, limit int) string {
	if len(value) <= limit {
		return value
	}
	return value[:limit] + "…"
}

func selectHongguoAppMedia(model map[string]any) (providerMedia, error) {
	variants := anyList(model["video_list"])
	if rows, ok := model["video_list"].(map[string]any); ok && len(variants) == 0 {
		keys := make([]string, 0, len(rows))
		for key := range rows {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			variants = append(variants, rows[key])
		}
	}
	duration, _ := strconv.ParseFloat(mapString(model, "video_duration", "duration"), 64)
	var keyErr error
	type scoredMedia struct {
		media providerMedia
		score int
	}
	var choices []scoredMedia
	for _, row := range variants {
		variant, _ := row.(map[string]any)
		meta := nestedMap(variant, "video_meta")
		codec := strings.ToLower(mapString(meta, "codec_type"))
		if codec == "bytevc2" || strings.Contains(strings.ToLower(mapString(variant, "gear_des_key")), "bytevc2") {
			continue
		}
		addresses := hongguoMediaAddresses(variant)
		if len(addresses) == 0 {
			continue
		}
		media := providerMedia{Referer: "https://novel.snssdk.com/", Duration: time.Duration(duration * float64(time.Second))}
		encryption := nestedMap(variant, "encrypt_info")
		spade := mapString(encryption, "spade_a")
		if spade != "" || encryption["encrypt"] == true || mapString(encryption, "encryption_method") == "cenc-aes-ctr" {
			var err error
			media.CENCKey, err = hongguoContentKey(spade)
			if err != nil {
				keyErr = err
				continue
			}
		}
		height, _ := strconv.Atoi(mapString(meta, "vheight"))
		if definition, err := strconv.Atoi(hongguoQualityNumber.FindString(mapString(meta, "definition"))); err == nil && definition > 0 {
			height = definition
		} else if width, _ := strconv.Atoi(mapString(meta, "vwidth")); width > 0 && (height == 0 || width < height) {
			height = width
		}
		media.Quality = height
		quality := height * 10
		if codec == "h264" || codec == "avc1" {
			quality++
		}
		for _, address := range addresses {
			media.URL = address
			choices = append(choices, scoredMedia{media: media, score: quality})
		}
	}
	if len(choices) > 0 {
		sort.SliceStable(choices, func(i, j int) bool { return choices[i].score > choices[j].score })
		selected := choices[0].media
		for _, choice := range choices {
			selected.Variants = append(selected.Variants, choice.media)
		}
		return selected, nil
	}
	if keyErr != nil {
		return providerMedia{}, fmt.Errorf("红果 App 媒体密钥不可用: %w", keyErr)
	}
	return providerMedia{}, errors.New("红果 App 未返回兼容的媒体，已跳过不支持的编码")
}

func hongguoMediaAddresses(info map[string]any) []string {
	var addresses []string
	seen := map[string]bool{}
	var add func(any)
	add = func(value any) {
		switch value := value.(type) {
		case string:
			address := strings.TrimSpace(value)
			if len(address) > 8192 {
				return
			}
			if !isProviderHTTPMediaURL(address) {
				decoded, err := decodeHongguoBase64(address)
				if err != nil {
					return
				}
				address = strings.TrimSpace(string(decoded))
			}
			if isProviderHTTPMediaURL(address) && !seen[address] {
				seen[address] = true
				addresses = append(addresses, address)
			}
		case []any:
			for _, item := range value {
				add(item)
			}
		}
	}
	for _, key := range []string{"main_url", "backup_url", "backup_url_1", "backup_url_2", "backup_urls", "url_list"} {
		add(info[key])
	}
	return addresses
}
