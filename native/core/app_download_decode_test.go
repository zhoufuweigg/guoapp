package core

import (
	"context"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

func TestNativeDownloadedEncryptedHLSDecodesWithSourceOffline(t *testing.T) {
	ffmpeg, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("FFmpeg is required for the synthetic offline decoder check")
	}
	source := t.TempDir()
	key := []byte("0123456789abcdef")
	keyFile := filepath.Join(source, "test.key")
	if err := os.WriteFile(keyFile, key, 0600); err != nil {
		t.Fatal(err)
	}
	keyInfo := filepath.Join(source, "key-info.txt")
	if err := os.WriteFile(keyInfo, []byte("denied.key\n"+keyFile+"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	generate := exec.CommandContext(ctx, ffmpeg, "-v", "error", "-y",
		"-f", "lavfi", "-i", "color=c=black:s=160x90:r=10",
		"-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100", "-t", "3",
		"-c:v", "libx264", "-threads", "1", "-g", "10", "-pix_fmt", "yuv420p", "-c:a", "aac",
		"-hls_time", "1", "-hls_list_size", "0", "-hls_key_info_file", keyInfo,
		"-hls_segment_filename", filepath.Join(source, "seg-%d.ts"), filepath.Join(source, "index.m3u8"))
	if output, err := generate.CombinedOutput(); err != nil {
		t.Fatalf("generate: %v\n%s", err, output)
	}
	server := http.FileServer(http.Dir(source))
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/denied.key" {
			t.Error("resolved AES key was fetched again")
			http.NotFound(w, r)
			return
		}
		server.ServeHTTP(w, r)
	}))
	t.Cleanup(upstream.Close)
	manager := downloadTestManager(t)
	manager.resolve = func(context.Context, nativeDownloadJob) (providerMedia, error) {
		return providerMedia{URL: upstream.URL + "/index.m3u8", HLSKey: key}, nil
	}
	input := downloadTestInput(1)
	if _, err := manager.enqueue(input); err != nil {
		t.Fatal(err)
	}
	jobs := waitDownloads(t, manager, func(jobs []nativeDownloadJob) bool { return len(jobs) == 1 && jobs[0].State == "converting" })
	upstream.Close()
	work, err := manager.beginConversion(jobs[0].ID)
	if err != nil || work.Key != "" {
		t.Fatalf("conversion input: %+v %v", work, err)
	}
	convert := exec.CommandContext(ctx, ffmpeg, "-v", "error", "-y",
		"-protocol_whitelist", "file,crypto,data", "-allowed_extensions", "ALL", "-extension_picky", "0",
		"-i", work.Input, "-map", "0:v:0", "-map", "0:a:0?", "-c", "copy", "-movflags", "+faststart", work.Output)
	if output, err := convert.CombinedOutput(); err != nil {
		t.Fatalf("offline AES HLS conversion: %v\n%s", err, output)
	}
	if err := manager.finishConversion(jobs[0].ID, "done"); err != nil {
		t.Fatal(err)
	}
	plan, found, err := manager.localPlan(input.Drama.ID, 1)
	if err != nil || !found || !plan.Local || filepath.Ext(plan.URL) != ".mp4" {
		t.Fatalf("offline plan: %+v %v", plan, err)
	}
	decode := exec.CommandContext(ctx, ffmpeg, "-v", "error", "-i", plan.URL, "-f", "null", "-")
	if output, err := decode.CombinedOutput(); err != nil {
		t.Fatalf("offline AES HLS decode: %v\n%s", err, output)
	}
}

func TestNativeDownloadedCENCConvertsToPlainMP4(t *testing.T) {
	ffmpeg, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("FFmpeg is required for the synthetic offline decoder check")
	}
	source := t.TempDir()
	key := []byte("0123456789abcdef")
	encrypted := filepath.Join(source, "media.mp4")
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	generate := exec.CommandContext(ctx, ffmpeg, "-v", "error", "-y",
		"-f", "lavfi", "-i", "color=c=black:s=160x90:r=10",
		"-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100", "-t", "3",
		"-c:v", "libx264", "-threads", "1", "-pix_fmt", "yuv420p", "-c:a", "aac",
		"-encryption_scheme", "cenc-aes-ctr", "-encryption_key", hex.EncodeToString(key),
		"-encryption_kid", "00112233445566778899aabbccddeeff", encrypted)
	if output, err := generate.CombinedOutput(); err != nil {
		t.Fatalf("generate: %v\n%s", err, output)
	}
	upstream := httptest.NewServer(http.FileServer(http.Dir(source)))
	t.Cleanup(upstream.Close)
	manager := downloadTestManager(t)
	manager.resolve = func(context.Context, nativeDownloadJob) (providerMedia, error) {
		return providerMedia{URL: upstream.URL + "/media.mp4", CENCKey: key}, nil
	}
	input := downloadTestInput(1)
	if _, err := manager.enqueue(input); err != nil {
		t.Fatal(err)
	}
	jobs := waitDownloads(t, manager, func(jobs []nativeDownloadJob) bool { return len(jobs) == 1 && jobs[0].State == "converting" })
	upstream.Close()
	work, err := manager.beginConversion(jobs[0].ID)
	if err != nil || work.Key != hex.EncodeToString(key) {
		t.Fatalf("conversion input: %+v %v", work, err)
	}
	convert := exec.CommandContext(ctx, ffmpeg, "-v", "error", "-y", "-decryption_key", work.Key,
		"-i", work.Input, "-map", "0:v:0", "-map", "0:a:0?", "-c", "copy", "-movflags", "+faststart", work.Output)
	if output, err := convert.CombinedOutput(); err != nil {
		t.Fatalf("offline CENC conversion: %v\n%s", err, output)
	}
	if err := manager.finishConversion(jobs[0].ID, "done"); err != nil {
		t.Fatal(err)
	}
	plan, found, err := manager.localPlan(input.Drama.ID, 1)
	if err != nil || !found || plan.Key != "" {
		t.Fatalf("offline plan: %+v %v", plan, err)
	}
	decode := exec.CommandContext(ctx, ffmpeg, "-v", "error", "-xerror", "-i", plan.URL, "-f", "null", "-")
	if output, err := decode.CombinedOutput(); err != nil || len(output) > 0 {
		t.Fatalf("converted CENC still needs a key: %v\n%s", err, output)
	}
}
