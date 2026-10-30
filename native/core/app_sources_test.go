package core

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

type sourceFixtureTransport func(*http.Request) (*http.Response, error)

func (transport sourceFixtureTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	return transport(request)
}

func sourceFixtureResponse(request *http.Request, status int, body string) *http.Response {
	return &http.Response{StatusCode: status, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(body)), ContentLength: int64(len(body)), Request: request}
}

func sourceFixtureDownloader(t *testing.T, transport sourceFixtureTransport) *Downloader {
	t.Helper()
	d := &Downloader{cfg: Config{dataDir: t.TempDir(), Retries: 1, PageSize: 30, MaxPagesPerSort: 1},
		client: &http.Client{Transport: transport}, limiter: newRequestLimiter(3, 0), providerHosts: map[string]string{}}
	registerHongguoFixtureDevices(d)
	return d
}

func registerHongguoFixtureDevices(d *Downloader) {
	state := &d.hongguoClient().state
	state.Registered, state.HelperDeviceID, state.HelperInstallID = true, "424242", "4242429"
}

func sourceFixtureEngine(t *testing.T, transport sourceFixtureTransport) *nativeEngine {
	t.Helper()
	engine, err := newNativeEngine(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	engine.downloader.client.Transport = transport
	engine.downloader.limiter = newRequestLimiter(3, 0)
	engine.downloader.cfg.Retries = 1
	registerHongguoFixtureDevices(engine.downloader)
	return engine
}

func TestSourceUpdatesPreservePagesOtherSourcesAndMetadata(t *testing.T) {
	engine := sourceFixtureEngine(t, func(request *http.Request) (*http.Response, error) {
		if !strings.Contains(request.URL.Path, "/api/videos/category/") {
			return nil, errors.New("only catalog text is allowed")
		}
		id := "new"
		if request.URL.Query().Get("page") == "3" {
			id = "continued"
		}
		return sourceFixtureResponse(request, 200, fmt.Sprintf(`{"data":[{"id":%q,"title":"合成短剧","desc":"完整资料","totalEpisode":2}]}`, id)), nil
	})
	engine.catalogs[sourceHuangguoAI] = []nativeDrama{{ID: "huangguoai:old", Source: sourceHuangguoAI, Title: "原有短剧", Description: "保留资料", Episodes: 2}}
	engine.catalogStates[sourceHuangguoAI] = nativeCatalogState{Page: 2, HasMore: true}
	engine.catalogs[sourceHongguo] = []nativeDrama{{ID: "hongguo:1", Source: sourceHongguo, Title: "其他站源"}}
	for _, page := range []int{1, 3} {
		if _, err := engine.nativeCatalog(context.Background(), nativeInput{Source: sourceHuangguoAI, Page: page, Force: true}); err != nil {
			t.Fatal(err)
		}
	}
	page := engine.nativeCached(sourceHuangguoAI)
	if len(page.Items) != 3 || page.Page != 3 || page.HasMore {
		t.Fatalf("lost refresh/tail state: %+v", page)
	}
	if len(engine.nativeCached(sourceHongguo).Items) != 1 {
		t.Fatal("updated another source")
	}
	engine.saveCatalogCache(sourceHuangguoAI, &nativeCatalogResult{Items: []nativeDrama{{ID: "huangguoai:old", Title: "新名称"}}, Page: 1, HasMore: true})
	page = engine.nativeCached(sourceHuangguoAI)
	if page.Page != 3 || page.HasMore || len(page.Items) != 3 || page.Items[0].Description != "保留资料" {
		t.Fatal("head refresh discarded cached metadata or pagination", page)
	}
}

func TestSourceBackoffUsesRelativeTimeAndRetainsTypedError(t *testing.T) {
	backoff := &requestBackoff{host: "huangguo.video", status: 403, until: time.Now().Add(time.Minute)}
	if !strings.Contains(backoff.Error(), "秒后") || strings.Contains(backoff.Error(), backoff.until.Format("15:04:05")) {
		t.Fatal("retry time depends on native timezone")
	}
	var restored *requestBackoff
	if !errors.As(publicError(fmt.Errorf("playlist: %w", backoff)), &restored) {
		t.Fatal("redaction discarded structured retry time")
	}
}
