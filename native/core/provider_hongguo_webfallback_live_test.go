package core

import (
	"context"
	"os"
	"testing"
	"time"
)

// 红果网页回退路由的实网校验：App 接口失败时，二级分类按路由回退到
// 网页版分类页（SSR），解析出的剧集应与真人剧/漫剧/AI剧分类对应。
func TestLiveHongguoWebFallbackRoutes(t *testing.T) {
	if os.Getenv("CHECK_LIVE_PROVIDERS") != "true" {
		t.Skip("set CHECK_LIVE_PROVIDERS=true to touch live hongguo web category pages")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	for _, category := range []string{"", "short_play", "comic_series", "ai_series"} {
		category := category
		t.Run("category="+category, func(t *testing.T) {
			routes := hongguoWebFallbackRoutes(category)
			if len(routes) == 0 {
				t.Fatalf("no fallback routes for category %q", category)
			}
			seen := map[string]bool{}
			total := 0
			for _, route := range routes {
				items, _, err := engine.downloader.fetchHongguoCategoryPage(ctx, route.path+"?page=1", route.name)
				if err != nil {
					t.Fatalf("route %s failed: %v", route.path, err)
				}
				if len(items) == 0 {
					t.Fatalf("route %s returned no dramas", route.path)
				}
				for _, drama := range items {
					if !seen[drama.ID] {
						seen[drama.ID] = true
						total++
					}
				}
			}
			if total == 0 {
				t.Fatal("no dramas parsed from fallback routes")
			}
			t.Logf("category %q: %d unique dramas across %d routes", category, total, len(routes))
		})
	}
}
