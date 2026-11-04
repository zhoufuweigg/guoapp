package core

import (
	"encoding/base64"
	"strings"
	"testing"
)

func TestHongguoVideoModelVariants(t *testing.T) {
	list := []any{map[string]any{"main_url": "https://example.test/a.mp4"}}

	t.Run("object model", func(t *testing.T) {
		model, err := hongguoVideoModel(map[string]any{
			"video_model": map[string]any{"video_list": list, "video_duration": "60"},
		})
		if err != nil || len(anyList(model["video_list"])) != 1 {
			t.Fatalf("model=%v err=%v", model, err)
		}
	})

	t.Run("base64 model", func(t *testing.T) {
		encoded := base64.StdEncoding.EncodeToString([]byte(`{"video_list":[{"main_url":"https://example.test/a.mp4"}]}`))
		model, err := hongguoVideoModel(map[string]any{"video_model": encoded})
		if err != nil || len(anyList(model["video_list"])) != 1 {
			t.Fatalf("model=%v err=%v", model, err)
		}
	})

	t.Run("flat list", func(t *testing.T) {
		model, err := hongguoVideoModel(map[string]any{"video_list": list, "video_duration": 60})
		if err != nil || len(anyList(model["video_list"])) != 1 {
			t.Fatalf("model=%v err=%v", model, err)
		}
	})

	// video_model 只带时长、列表平铺在 data 上时，也应合并而不是放弃。
	t.Run("partial model with flat list", func(t *testing.T) {
		model, err := hongguoVideoModel(map[string]any{
			"video_model": map[string]any{"video_duration": 60},
			"video_list":  list,
		})
		if err != nil || len(anyList(model["video_list"])) != 1 {
			t.Fatalf("model=%v err=%v", model, err)
		}
		if mapString(model, "video_duration") != "60" {
			t.Fatalf("时长丢失: %v", model)
		}
	})

	// 明文 JSON 字符串（服务端实测下发格式，status:10 为正常播放模型状态）。
	t.Run("plain json string", func(t *testing.T) {
		model, err := hongguoVideoModel(map[string]any{
			"video_model": `{"status":10,"message":"success","video_list":[{"main_url":"https://example.test/a.mp4"}]}`,
		})
		if err != nil || len(anyList(model["video_list"])) != 1 {
			t.Fatalf("model=%v err=%v", model, err)
		}
	})

	t.Run("invalid payload", func(t *testing.T) {
		_, err := hongguoVideoModel(map[string]any{"video_model": "!!!"})
		if err == nil || !strings.Contains(err.Error(), "格式异常") {
			t.Fatalf("err=%v", err)
		}
	})
}
