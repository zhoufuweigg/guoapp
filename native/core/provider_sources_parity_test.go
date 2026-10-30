package core

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"testing"
	"time"
)

func providerParityDownloader(t *testing.T, transport func(*http.Request, url.Values) (*http.Response, error)) *Downloader {
	t.Helper()
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		form := request.URL.Query()
		if request.Body != nil {
			body, err := io.ReadAll(request.Body)
			if err != nil {
				t.Fatal(err)
			}
			bodyForm, _ := url.ParseQuery(string(body))
			for key, values := range bodyForm {
				form[key] = append(form[key], values...)
			}
		}
		return transport(request, form)
	})
	d.cfg.HuangjuAPIURL = "https://api.huangju.test"
	d.cfg.HuangjuURL = "https://huangju.test"
	d.cfg.YeguoURL = "https://yeguo.test"
	d.cfg.DSDURL = "https://dsd.test"
	return d
}

func TestProviderSourceParsesTextFixturesAndRejectsMismatchedIdentity(t *testing.T) {
	huangjuRow := map[string]any{"id": "77", "slug": "sample-drama", "title": "剧果样本", "totalEpisodes": json.Number("2"), "status": "completed", "categories": []any{"热播"}, "year": "2026", "score": "8.5"}
	drama, err := huangjuDramaFromMap(huangjuRow, huangjuBaseURL, "")
	if err != nil || drama.ID != "huangju:sample-drama-77" || drama.ReleaseStatus != "finished" || drama.EpisodeCount != 2 || drama.ChannelName != "剧果" {
		t.Fatalf("huangju text row parsed incorrectly: %+v %v", drama, err)
	}
	if _, err := huangjuDramaFromMap(huangjuRow, huangjuBaseURL, "sample-drama-78"); err == nil {
		t.Fatal("huangju accepted a mismatched source id")
	}
	if validHuangjuID("bad:value") || !validHuangjuID(strings.Repeat("a", 450)) || validHuangjuID(strings.Repeat("a", 451)) {
		t.Fatal("huangju id validation changed")
	}
	yeguoRow := map[string]any{"video_id": "123", "title": "野果样本", "episode_count": "12", "serialize_status": "2", "play_count_text": "3.4万", "published_at": "2026-09-23T10:20:30+08:00", "is_vip": "1", "tags": []any{"甜宠", "重生"}}
	yeguo, err := yeguoDramaFromMap(yeguoRow, yeguoBaseURL)
	if err != nil || yeguo.ID != "yeguo:123" || yeguo.ReleaseStatus != "finished" || yeguo.Views != "3.4万次播放" || yeguo.OnlineDate != "2026-09-23" || yeguo.VIP == nil || !*yeguo.VIP {
		t.Fatalf("yeguo text row parsed incorrectly: %+v %v", yeguo, err)
	}
	page := "https://www.dsd.com.se/index.php/vod/type/id/9/page/1.html"
	action, values, valid := dsdRouteParameters(page, "/index.php/vod/play/id/456/sid/1/nid/2.html?extra=1")
	if !valid || action != "play" || values["id"] != "456" || values["sid"] != "1" || values["nid"] != "2" || values["extra"] != "1" {
		t.Fatal("dsd route parser lost valid fields", action, values, valid)
	}
	if _, _, valid = dsdRouteParameters(page, "https://other.example/index.php/vod/play/id/456/sid/1/nid/2.html"); valid {
		t.Fatal("dsd accepted a cross-origin route")
	}
}

func TestYeguoDomainAliasesAndDefaultEndpoint(t *testing.T) {
	if got := (&Downloader{cfg: defaultConfig()}).providerBaseURL(sourceYeguo); got != "https://analyze.buxefaex.cc" {
		t.Fatalf("unexpected default yeguo endpoint: %s", got)
	}
	for _, address := range []string{
		"https://analyze.buxefaex.cc/",
		"https://some-line.buxefaex.cc/drama/video/1/",
		"https://some-backup.fzchosdi.cc/drama/video/1/",
		"https://some-backup.lwblvxvy.cc/drama/video/1/",
		"https://delta.ygrwdsgt.cc/",
		"https://yeguodj.com/",
		"https://ygdj7.com/",
		"https://ygdj15.com/",
	} {
		if got := providerSourceForURL(address); got != sourceYeguo {
			t.Fatalf("yeguo domain was not recognized: %s -> %s", address, got)
		}
	}
	for _, alias := range []string{
		"analyze.buxefaex.cc",
		"delta.ygrwdsgt.cc",
		"yeguodj.com",
		"ygdj7.com",
		"ygdj15.com",
	} {
		if got := canonicalProviderSource(alias); got != sourceYeguo {
			t.Fatalf("yeguo source alias was not canonicalized: %s -> %s", alias, got)
		}
	}
}

func TestYeguoTransitPageDiscoversCurrentLineDomains(t *testing.T) {
	encoded := base64.StdEncoding.EncodeToString([]byte(`<script>
words = 'abandon,ability,analyze,chair'.split(',');
lineAry = Vx.map(Vx.range(1, 3), function () { return location.protocol + '//' + words.random() + '.buxefaex.cc' });
backupLine = Vx.map(Vx.range(1, 3), function () { return location.protocol + '//' + words.random() + '.fzchosdi.cc'; });
spareLine = Vx.map(Vx.range(1, 3), function () { return location.protocol + '//' + words.random() + '.lwblvxvy.cc'; });
</script>`))
	sites := yeguoTransitSites(`<script>document.write(Base64.decode("` + encoded + `"));</script>`)
	want := []string{"https://analyze.buxefaex.cc", "https://ability.buxefaex.cc", "https://abandon.buxefaex.cc", "https://analyze.fzchosdi.cc", "https://analyze.lwblvxvy.cc"}
	for _, site := range want {
		found := false
		for _, candidate := range sites {
			found = found || candidate == site
		}
		if !found {
			t.Fatalf("transit discovery missed %s in %v", site, sites)
		}
	}
}

func TestYeguoCatalogAcceptsSourcePageSize(t *testing.T) {
	d := providerParityDownloader(t, func(request *http.Request, form url.Values) (*http.Response, error) {
		if request.URL.Host != "api.yeguo.test" || request.URL.Path != "/api/theater/exploreList" {
			t.Fatalf("unexpected yeguo request: %s", request.URL.String())
		}
		if request.Method != http.MethodPost {
			t.Fatalf("yeguo catalog must use POST for pagination, got %s", request.Method)
		}
		rows := make([]any, 0, 30)
		for index := 1; index <= 30; index++ {
			id := strconv.Itoa(9000 + index)
			rows = append(rows, map[string]any{"video_id": id, "title": "野果目录样本 " + id, "episode_count": "6", "serialize_status": "2"})
		}
		body, _ := json.Marshal(map[string]any{"status": "1", "data": map[string]any{"list": rows, "limit": 20, "total": 30, "has_more": "0"}})
		return sourceFixtureResponse(request, http.StatusOK, string(body)), nil
	})
	d.yeguoClient().access = &yeguoAccess{base: "https://api.yeguo.test", identifier: "fixture-trace", loadedAt: time.Now()}
	items, more, err := d.fetchYeguoCatalogPage(context.Background(), 1, "", "")
	if err != nil || more || len(items) != 30 {
		t.Fatalf("yeguo source-sized page rejected: items=%d more=%t err=%v", len(items), more, err)
	}
}

func TestHuangjuPlaybackUsesSignedCookiesForPlaylist(t *testing.T) {
	var sawCookie bool
	var mediaURL string
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		switch request.URL.Path {
		case "/auth/guest":
			response.Header().Set("Content-Type", "application/json")
			_, _ = io.WriteString(response, `{"token":"guest-token"}`)
		case "/play/episode-1":
			response.Header().Add("Set-Cookie", "CloudFront-Policy=policy; Path=/; Max-Age=3600")
			response.Header().Add("Set-Cookie", "CloudFront-Signature=signature; Path=/; Max-Age=3600")
			response.Header().Add("Set-Cookie", "CloudFront-Key-Pair-Id=keypair; Path=/; Max-Age=3600")
			response.Header().Set("Content-Type", "application/json")
			_, _ = io.WriteString(response, `{"url":`+strconv.Quote(mediaURL)+`,"expiresAt":`+strconv.FormatInt(time.Now().Add(time.Hour).Unix(), 10)+`}`)
		case "/media.m3u8":
			sawCookie = strings.Contains(request.Header.Get("Cookie"), "CloudFront-Policy=policy") &&
				strings.Contains(request.Header.Get("Cookie"), "CloudFront-Signature=signature") &&
				strings.Contains(request.Header.Get("Cookie"), "CloudFront-Key-Pair-Id=keypair")
			if !sawCookie {
				t.Fatalf("missing signed media cookies: %s", request.Header.Get("Cookie"))
			}
			response.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
			_, _ = io.WriteString(response, "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\nsegment.ts\n#EXT-X-ENDLIST\n")
		default:
			t.Fatalf("unexpected route: %s", request.URL.Path)
		}
	}))
	defer server.Close()
	mediaURL = server.URL + "/media.m3u8"
	d := &Downloader{cfg: Config{HuangjuAPIURL: server.URL, HuangjuURL: "https://huangju.test"}, client: server.Client(), limiter: newRequestLimiter(3, 0), providerHosts: map[string]string{}}
	media, err := d.resolveHuangjuMedia(context.Background(), Task{DramaID: providerDramaID(sourceHuangju, "sample-77"), Chapter: Chapter{ID: providerChapterID(sourceHuangju, "sample-77", "episode-1")}})
	if err != nil || !sawCookie || media.Playlist == "" || !strings.HasPrefix(media.Playlist, "#EXTM3U") {
		t.Fatalf("huangju playback was not resolved through signed playlist: %+v %v", media, err)
	}
}

func TestProviderMediaCredentialsLimitOriginAndUseBackupAddresses(t *testing.T) {
	primary := "https://media.example.test/main.mp4"
	backup := "https://media.example.test/backup.mp4"
	model := map[string]any{"video_duration": "6", "video_list": []any{map[string]any{
		"main_url": "invalid", "backup_url": base64.StdEncoding.EncodeToString([]byte(primary)), "backup_urls": []any{backup},
		"video_meta": map[string]any{"codec_type": "h264", "definition": "720p"},
	}}}
	media, err := selectHongguoAppMedia(model)
	if err != nil || media.URL != primary || len(media.Variants) != 2 || media.Variants[1].URL != backup || media.Duration != 6*time.Second {
		t.Fatalf("hongguo backup media fields were lost: %+v %v", media, err)
	}
	credentials := &providerMediaCredentials{origin: "https://media.example.test", cookie: "Signed=fixture", referer: "https://source.example.test/page", userAgent: "Agent"}
	request, _ := http.NewRequest(http.MethodGet, "https://media.example.test/part", nil)
	if err := credentials.apply(request); err != nil || request.Header.Get("Cookie") != "Signed=fixture" || request.Header.Get("Origin") != "https://source.example.test" || request.Header.Get("User-Agent") != "Agent" {
		t.Fatal("credentials not applied on exact origin", err, request.Header)
	}
	other, _ := http.NewRequest(http.MethodGet, "https://media.example.test:444/part", nil)
	other.Header.Set("Cookie", "old=value")
	if err := credentials.apply(other); err != nil || other.Header.Get("Cookie") != "" {
		t.Fatal("credentials leaked to another origin", err, other.Header)
	}
}

func TestProviderDSDMediaSigningPropagatesFetchErrors(t *testing.T) {
	d := rankingTestDownloader(t, func(request *http.Request) (*http.Response, error) {
		if !strings.Contains(request.URL.Path, "/addons/vplayer/") {
			t.Fatalf("unexpected request: %s", request.URL.String())
		}
		return rankingHTTPResponse(request, http.StatusBadGateway, "unavailable"), nil
	})
	_, found, err := d.signDSDMedia(context.Background(), "https://media.example.test/video/index.m3u8", "https://www.dsd.com.se/index.php/vod/play/id/1/sid/1/nid/1.html", "https://www.dsd.com.se")
	if err == nil || found {
		t.Fatal("dsd signing failure was swallowed", found, err)
	}
	if path := dsdVplayerMediaPath("https://media.example.test/video/index.m3u8?token=a%2Fb"); path != "/video/index.m3u8?token=a%2Fb" {
		t.Fatal("dsd media path changed", path)
	}
}
