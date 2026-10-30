package core

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

func streamDiagnosticEvents(t *testing.T, stream *nativeStreamServer) ([]diagnosticEvent, string) {
	t.Helper()
	data, err := os.ReadFile(stream.downloader.diagnostics.path)
	if err != nil {
		t.Fatal(err)
	}
	var events []diagnosticEvent
	for _, line := range strings.Split(strings.TrimSpace(string(data)), "\n") {
		var event diagnosticEvent
		if err := json.Unmarshal([]byte(line), &event); err != nil {
			t.Fatal(err)
		}
		events = append(events, event)
	}
	return events, string(data)
}

func TestNativeStreamDiagnosticsRewriteAndReadFailures(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
		if r.URL.Path == "/truncated.m3u8" {
			w.Header().Set("Content-Length", "1000")
			io.WriteString(w, "#EXTM3U\n")
			return
		}
		io.WriteString(w, "not-a-playlist")
	}))
	defer upstream.Close()
	engine, err := newNativeEngine(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	stream, err := newNativeStreamServer(engine.downloader)
	if err != nil {
		t.Fatal(err)
	}
	defer stream.server.Close()
	for _, media := range []providerMedia{
		{URL: upstream.URL + "/truncated.m3u8"},
		{URL: upstream.URL + "/invalid.m3u8"},
		{URL: upstream.URL + "/cached.m3u8", Playlist: "#EXTM3U\nftp://invalid.test/segment.ts\n"},
	} {
		address, token := stream.nativeOpen(media)
		response, err := http.Get(address)
		if err != nil {
			t.Fatal(err)
		}
		io.Copy(io.Discard, response.Body)
		response.Body.Close()
		stream.nativeRelease(token)
		if response.StatusCode != http.StatusBadGateway {
			t.Fatalf("failure returned status %d", response.StatusCode)
		}
	}
	_, text := streamDiagnosticEvents(t, stream)
	for _, marker := range []string{"stream.upstream_read_error", "error=unexpected_eof", "stream.playlist_invalid", "stream.playlist_rewrite", "error=io_error"} {
		if !strings.Contains(text, marker) {
			t.Errorf("missing diagnostic %s", marker)
		}
	}
	for _, sample := range []struct {
		err  error
		want string
	}{
		{&net.DNSError{Err: "secret DNS error", Name: "private.test"}, "dns"},
		{&net.OpError{Op: "dial", Err: io.ErrUnexpectedEOF}, "connect"},
		{context.Canceled, "canceled"},
		{context.DeadlineExceeded, "deadline"},
	} {
		if got := nativeStreamError(sample.err); got != sample.want {
			t.Errorf("error category=%s want %s", got, sample.want)
		}
	}
}

func TestNativeStreamDiagnosticsHLSAssetsAndPrivacy(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/master.m3u8":
			w.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
			io.WriteString(w, "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=200000\nchild.m3u8?secret=hidden-query\n")
		case "/child.m3u8":
			w.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
			io.WriteString(w, "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"secret.key\"\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:3,\nsegment.ts\n#EXT-X-ENDLIST\n")
		case "/forbidden.ts":
			w.WriteHeader(http.StatusForbidden)
		default:
			w.Header().Set("Content-Type", "application/octet-stream")
			io.WriteString(w, "binary-media")
		}
	}))
	defer upstream.Close()
	engine, err := newNativeEngine(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	stream, err := newNativeStreamServer(engine.downloader)
	if err != nil {
		t.Fatal(err)
	}
	defer stream.server.Close()
	address, token := stream.nativeOpen(providerMedia{URL: upstream.URL + "/master.m3u8?token=hidden-query", HLSKey: []byte("hidden-key-bytes")})
	fetch := func(address string) (int, string) {
		t.Helper()
		request, _ := http.NewRequest(http.MethodGet, address, nil)
		request.Header.Set("Authorization", "Bearer hidden-auth")
		request.Header.Set("Cookie", "hidden-cookie")
		response, err := http.DefaultClient.Do(request)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		body, err := io.ReadAll(response.Body)
		if err != nil {
			t.Fatal(err)
		}
		return response.StatusCode, string(body)
	}
	read := func(address string) string {
		t.Helper()
		status, body := fetch(address)
		if status != http.StatusOK {
			t.Fatalf("status=%d body=%s", status, body)
		}
		return body
	}
	playlistURL := func(body string) string {
		for _, line := range strings.Split(body, "\n") {
			if strings.HasPrefix(line, "http:") {
				return line
			}
		}
		t.Fatal("missing rewritten media URL")
		return ""
	}
	child := read(playlistURL(read(address)))
	for index, match := range nativePlaylistURI.FindAllStringSubmatch(child, -1) {
		want := "binary-media"
		if index == 0 {
			want = "hidden-key-bytes"
		}
		if body := read(match[1]); body != want {
			t.Fatalf("key/map was treated as a playlist: %s", body)
		}
	}
	if body := read(playlistURL(child)); body != "binary-media" {
		t.Fatal("segment was treated as a playlist")
	}
	session := stream.sessions[token]
	keyURL := stream.nativeAsset(token, session, nativeStreamAsset{kind: "key", address: upstream.URL + "/remote.key", contentType: "application/octet-stream"})
	if body := read(keyURL); body != "binary-media" {
		t.Fatal("upstream key was treated as a playlist")
	}
	if _, err := os.Stat(stream.downloader.diagnostics.path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("successful playback wrote diagnostics: %v", err)
	}
	forbidden := stream.nativeAsset(token, session, nativeStreamAsset{kind: "segment", address: upstream.URL + "/forbidden.ts?secret=hidden-query"})
	if status, _ := fetch(forbidden); status != http.StatusForbidden {
		t.Fatalf("forbidden segment returned status %d", status)
	}
	stream.nativeRelease(token)
	events, text := streamDiagnosticEvents(t, stream)
	for _, secret := range []string{token, "hidden-query", "hidden-key-bytes", "hidden-auth", "hidden-cookie"} {
		if strings.Contains(text, secret) {
			t.Fatalf("diagnostic exposed %s", secret)
		}
	}
	if len(events) != 1 || events[0].Event != "stream.upstream_status" || events[0].HTTPStatus != http.StatusForbidden || !strings.Contains(events[0].Message, "asset=segment") {
		t.Fatalf("unexpected diagnostics: %s", text)
	}
}

func TestNativeStreamDiagnosticsCancellationAndHTTPFailure(t *testing.T) {
	entered := make(chan struct{})
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/slow.m3u8" {
			close(entered)
			<-r.Context().Done()
			return
		}
		w.WriteHeader(http.StatusForbidden)
	}))
	defer upstream.Close()
	engine, err := newNativeEngine(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	stream, err := newNativeStreamServer(engine.downloader)
	if err != nil {
		t.Fatal(err)
	}
	defer stream.server.Close()
	for _, name := range []string{"forbidden.m3u8", "slow.m3u8"} {
		address, token := stream.nativeOpen(providerMedia{URL: upstream.URL + "/" + name})
		done := make(chan int, 1)
		go func() {
			response, err := http.Get(address)
			if err != nil {
				done <- 0
				return
			}
			io.Copy(io.Discard, response.Body)
			response.Body.Close()
			done <- response.StatusCode
		}()
		if strings.HasPrefix(name, "slow") {
			select {
			case <-entered:
			case <-time.After(5 * time.Second):
				t.Fatal("upstream never entered")
			}
			stream.nativeRelease(token)
		}
		select {
		case status := <-done:
			if status != http.StatusForbidden && status != http.StatusBadGateway {
				t.Fatalf("unexpected status %d", status)
			}
		case <-time.After(5 * time.Second):
			t.Fatal("request did not finish after cancellation")
		}
		stream.nativeRelease(token)
	}
	_, text := streamDiagnosticEvents(t, stream)
	if !strings.Contains(text, "\"httpStatus\":403") {
		t.Error("missing upstream status diagnostic")
	}
	for _, marker := range []string{"canceled", "reason=release"} {
		if strings.Contains(text, marker) {
			t.Errorf("normal cancellation logged %s", marker)
		}
	}
	if nativeStreamError(context.DeadlineExceeded) != "deadline" {
		t.Fatal("deadline classification lost")
	}
}
