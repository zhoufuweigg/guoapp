package core

import (
	"context"
	"encoding/json"
	"net/http"
	"reflect"
	"sync"
	"testing"
)

func hongguoTagFixtureRow(id, show string) map[string]any {
	return map[string]any{"selector_item_id": id, "show_name": show}
}

func TestHongguoTagCategoriesFollowThePanel(t *testing.T) {
	var mu sync.Mutex
	panels := 0
	engine := sourceFixtureEngine(t, func(request *http.Request) (*http.Response, error) {
		query := request.URL.Query()
		if request.URL.Path != hongguoTagLandingPath || query.Get("category_id") != hongguoTagPanelCategory || query.Get("is_merged_landing_page") != "true" {
			t.Error("unexpected panel request", request.URL.Path, query)
		}
		mu.Lock()
		panels++
		mu.Unlock()
		body, _ := json.Marshal(map[string]any{"code": 0, "data": map[string]any{"selector": map[string]any{"rows": []any{
			map[string]any{"type": "mock", "items": []any{hongguoTagFixtureRow("cate_9", "预览")}},
			map[string]any{"type": "dialog_match_condition", "items": []any{hongguoTagFixtureRow("is_and_1", "满足全部")}},
			map[string]any{"type": "dialog_bottom", "items": []any{hongguoTagFixtureRow("cate_96", "甜宠"), hongguoTagFixtureRow("cate_36", "重生")}},
			map[string]any{"type": "dialog_bottom", "items": []any{hongguoTagFixtureRow("cate_36", "重生"), hongguoTagFixtureRow("cate_1", "都市"), hongguoTagFixtureRow("bad id", "无效")}},
		}}}})
		return sourceFixtureResponse(request, http.StatusOK, string(body)), nil
	})
	want := []nativeCategory{{Name: "全部"}}
	for _, genre := range hongguoAppGenres {
		want = append(want, nativeCategory{ID: genre.key, Name: genre.name})
	}
	want = append(want, nativeCategory{ID: "tag:cate_96", Name: "甜宠"}, nativeCategory{ID: "tag:cate_36", Name: "重生"}, nativeCategory{ID: "tag:cate_1", Name: "都市"})
	for range 2 {
		got, err := engine.nativeCategories(context.Background(), sourceHongguo, false)
		if err != nil || !reflect.DeepEqual(got, want) {
			t.Fatal("panel categories were not listed after the genres", err, got)
		}
	}
	if panels != 1 {
		t.Fatal("cached panel was requested again", panels)
	}
	if !validNativeCategory(sourceHongguo, "tag:cate_96") || validNativeCategory(sourceHongguo, "tag:is_and_1") || validNativeCategory(sourceHongguo, "cate_96") {
		t.Fatal("tag category validation is wrong")
	}
}

func TestHongguoTagPanelFailureKeepsGenres(t *testing.T) {
	engine := sourceFixtureEngine(t, func(request *http.Request) (*http.Response, error) {
		return sourceFixtureResponse(request, http.StatusOK, `{"code":101116,"message":"SERVICE_ERROR"}`), nil
	})
	got, err := engine.nativeCategories(context.Background(), sourceHongguo, false)
	if err != nil || len(got) != len(hongguoAppGenres)+1 {
		t.Fatal("genres were lost when the panel failed", err, got)
	}
}

func TestHongguoTagPagesContinueTheSession(t *testing.T) {
	var mu sync.Mutex
	var requests []string
	engine := sourceFixtureEngine(t, func(request *http.Request) (*http.Response, error) {
		query := request.URL.Query()
		mu.Lock()
		requests = append(requests, query.Get("selected_items")+"@"+query.Get("offset")+"#"+query.Get("session_id")+"/"+query.Get("client_req_type"))
		mu.Unlock()
		if request.URL.Path != hongguoTagLandingPath || query.Get("category_id") != "0" || query.Get("genre_type") != "130" {
			t.Error("unexpected tag request", request.URL.Path, query)
		}
		offset := query.Get("offset")
		next := map[string]int{"0": 12, "12": 24}[offset]
		body, _ := json.Marshal(map[string]any{"code": 0, "data": map[string]any{
			"has_more": offset == "0", "offset": next, "session_id": "fixture-session",
			"video_info": []any{map[string]any{"series_id": "70" + offset + "1", "title": "题材剧 " + offset, "cover": "https://example.test/cover.jpg", "episode_cnt": 60}},
		}})
		return sourceFixtureResponse(request, http.StatusOK, string(body)), nil
	})
	first, err := engine.nativeCatalog(context.Background(), nativeInput{Source: sourceHongguo, Category: "tag:cate_96", Page: 1})
	if err != nil || len(first.Items) != 1 || !first.HasMore || first.Items[0].Title != "题材剧 0" {
		t.Fatal("first tag page was not parsed", err, first.Items, first.HasMore)
	}
	second, err := engine.nativeCatalog(context.Background(), nativeInput{Source: sourceHongguo, Category: "tag:cate_96", Page: 2})
	if err != nil || len(second.Items) != 1 || second.HasMore || second.Items[0].Title != "题材剧 12" {
		t.Fatal("second tag page did not continue", err, second.Items, second.HasMore)
	}
	if cached := engine.nativeCached(nativeCatalogKey(sourceHongguo, "tag:cate_96")); len(cached.Items) != 2 {
		t.Fatal("tag pages were not cached together", cached.Items)
	}
	want := []string{"cate_96@0#/3", "cate_96@12#fixture-session/2"}
	if !reflect.DeepEqual(requests, want) {
		t.Fatal("tag paging lost its cursor", requests)
	}
}
