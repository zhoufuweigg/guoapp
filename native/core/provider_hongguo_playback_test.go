package core

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestHongguoPlaybackClientDisablesHTTP2 确认备用取流通道禁用了 HTTP/2，
// 否则第三方代理（djapi 等）不支持 ALPN 时会报 “tls: no application protocol”。
func TestHongguoPlaybackClientDisablesHTTP2(t *testing.T) {
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatalf("newNativeEngine: %v", err)
	}
	transport, ok := engine.downloader.playbackClient.Transport.(*http.Transport)
	if !ok {
		t.Fatalf("playbackClient transport 类型错误: %T", engine.downloader.playbackClient.Transport)
	}
	if transport.ForceAttemptHTTP2 {
		t.Fatal("playbackClient 仍强制尝试 HTTP/2")
	}
	if transport.TLSNextProto == nil {
		t.Fatal("playbackClient 未设置空 TLSNextProto（HTTP/2 关闭标记）")
	}
}

// TestHongguoPlaybackTextHTTP1 用 HTTP/1.1 本地服务验证取流文本读取正常，
// 模拟被标准 h2 协商排除后的第三方代理场景。
func TestHongguoPlaybackTextHTTP1(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"parse":null,"jx":null,"key_urls":[]}`))
	}))
	defer server.Close()

	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatalf("newNativeEngine: %v", err)
	}
	body, err := engine.downloader.fetchHongguoPlaybackText(context.Background(), server.URL)
	if err != nil {
		t.Fatalf("fetchHongguoPlaybackText: %v", err)
	}
	if body == "" {
		t.Fatal("取流文本为空")
	}
}
