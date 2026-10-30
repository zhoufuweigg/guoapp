package core

import (
	"context"
	"encoding/json"
	"net/http"
	"reflect"
	"slices"
	"strconv"
	"sync"
	"testing"
)

func TestHongguoAppRequestRetriesEmptyBody(t *testing.T) {
	calls := 0
	transport := sourceFixtureTransport(func(request *http.Request) (*http.Response, error) {
		calls++
		if calls == 1 {
			return sourceFixtureResponse(request, http.StatusOK, ""), nil
		}
		return sourceFixtureResponse(request, http.StatusOK, `{"code":0,"data":{}}`), nil
	})
	engine := sourceFixtureEngine(t, transport)
	engine.downloader.cfg.Retries = 2
	if _, err := engine.downloader.hongguoAppRequest(context.Background(), http.MethodGet, "/reading/bookapi/bookmall/tab/v1/", nil, nil); err != nil || calls != 2 {
		t.Fatal("empty body was not retried", err, calls)
	}
}

func TestHongguoFeedRecommendationsContinueDoubleColCell(t *testing.T) {
	const cellID = "6952850996422770718"
	card := func(id string) any {
		return map[string]any{"group_id_type": 9, "video_data": []any{map[string]any{"series_id": id, "title": "合成推荐 " + id}}}
	}
	changes := map[string]map[string]any{
		"6":  {"has_more": true, "next_offset": 12, "cell_view": map[string]any{"cell_data": []any{card("9001")}}},
		"12": {"has_more": true, "next_offset": 18, "cell_view": map[string]any{"cell_data": []any{card("9002")}}},
		"18": {"has_more": true, "next_offset": 24, "cell_view": map[string]any{"cell_data": []any{card("9003")}}},
		"24": {"has_more": false, "next_offset": 30, "cell_view": map[string]any{"cell_data": []any{card("9004")}}},
	}
	var mu sync.Mutex
	var requests []string
	transport := sourceFixtureTransport(func(request *http.Request) (*http.Response, error) {
		query := request.URL.Query()
		signed := request.Header.Get("X-Gorgon") != ""
		mu.Lock()
		requests = append(requests, request.URL.Path+"@"+query.Get("offset")+"#"+query.Get("device_id"))
		mu.Unlock()
		var data map[string]any
		switch request.URL.Path {
		case hongguoBookmallTabPath:
			if signed {
				t.Error("bookmall tab request was signed")
			}
			data = map[string]any{"tab_item": []any{map[string]any{"tab_type": 8, "session_id": "fixture-feed", "cell_data": []any{
				map[string]any{"cell_id": cellID, "show_type": 506, "next_offset": 6, "cell_data": []any{card("9001")}},
			}}}}
		case hongguoBookmallCellChangePath:
			if !signed || query.Get("cell_id") != cellID || query.Get("session_id") != "fixture-feed" || query.Get("show_type") != "506" || query.Get("client_req_type") != "2" || query.Get("change_type") != "0" {
				t.Error("cell change request lost its parameters", signed, query)
			}
			data = changes[query.Get("offset")]
		}
		body, _ := json.Marshal(map[string]any{"code": 0, "data": data})
		return sourceFixtureResponse(request, http.StatusOK, string(body)), nil
	})
	engine := sourceFixtureEngine(t, transport)
	first, err := engine.nativeRecommendations(context.Background(), nativeInput{Category: "find_drama"})
	if err != nil || len(first.Items) != 1 || !first.HasMore {
		t.Fatal("first double column page was not parsed", err, first.Items)
	}
	more, err := engine.nativeRecommendations(context.Background(), nativeInput{Category: "find_drama", Command: "more"})
	if err != nil || len(more.Items) != 2 || !more.HasMore || more.Items[1].Title != "合成推荐 9002" {
		t.Fatal("cell change did not continue past the repeated page", err, more.Items, more.HasMore)
	}
	last, err := engine.nativeRecommendations(context.Background(), nativeInput{Category: "find_drama", Command: "more"})
	if err != nil || len(last.Items) != 4 || last.HasMore || last.Items[2].Title != "合成推荐 9003" || last.Items[3].Title != "合成推荐 9004" {
		t.Fatal("paired pages were not merged in order", err, last.Items, last.HasMore)
	}
	primary, _, _ := engine.downloader.hongguoClient().device(false)
	helper, _, _ := engine.downloader.hongguoClient().device(true)
	slices.Sort(requests[1:3])
	slices.Sort(requests[3:5])
	want := []string{
		hongguoBookmallTabPath + "@0#" + primary,
		hongguoBookmallCellChangePath + "@12#" + helper, hongguoBookmallCellChangePath + "@6#" + primary,
		hongguoBookmallCellChangePath + "@18#" + primary, hongguoBookmallCellChangePath + "@24#" + helper,
	}
	if !reflect.DeepEqual(requests, want) {
		t.Fatal("unexpected request sequence", requests)
	}
}

func TestHongguoFeedRecommendationsSurviveHelperFailure(t *testing.T) {
	const cellID = "6952850996422770718"
	card := func(id string) any {
		return map[string]any{"group_id_type": 9, "video_data": []any{map[string]any{"series_id": id, "title": "合成推荐 " + id}}}
	}
	transport := sourceFixtureTransport(func(request *http.Request) (*http.Response, error) {
		query := request.URL.Query()
		var data map[string]any
		switch {
		case request.URL.Path == hongguoBookmallTabPath:
			data = map[string]any{"tab_item": []any{map[string]any{"tab_type": 8, "session_id": "fixture-feed", "cell_data": []any{
				map[string]any{"cell_id": cellID, "show_type": 506, "next_offset": 6, "cell_data": []any{card("9001")}},
			}}}}
		case query.Get("offset") == "6":
			data = map[string]any{"has_more": true, "next_offset": 12, "cell_view": map[string]any{"cell_data": []any{card("9002")}}}
		default:
			return sourceFixtureResponse(request, http.StatusBadGateway, ""), nil
		}
		body, _ := json.Marshal(map[string]any{"code": 0, "data": data})
		return sourceFixtureResponse(request, http.StatusOK, string(body)), nil
	})
	engine := sourceFixtureEngine(t, transport)
	if _, err := engine.nativeRecommendations(context.Background(), nativeInput{Category: "find_drama"}); err != nil {
		t.Fatal(err)
	}
	more, err := engine.nativeRecommendations(context.Background(), nativeInput{Category: "find_drama", Command: "more"})
	if err != nil || len(more.Items) != 2 || !more.HasMore {
		t.Fatal("helper failure broke the primary page", err, more.Items)
	}
	if state := engine.recommendations["find_drama"]; state.Query.Offset != 12 {
		t.Fatal("feed position skipped the failed helper page", state.Query.Offset)
	}
}

func TestHongguoFeedRecommendationsKeepSessionAndSkipRepeats(t *testing.T) {
	pages := map[string][]string{"0": {"9001", "9002"}, "1": {"9002"}, "2": {"9003"}}
	for _, feed := range hongguoRecommendationFeeds {
		t.Run(feed.key, func(t *testing.T) {
			var offsets []string
			transport := sourceFixtureTransport(func(request *http.Request) (*http.Response, error) {
				query := request.URL.Query()
				if request.URL.Path != "/reading/bookapi/bookmall/tab/v1/" || query.Get("tab_type") != feed.tabType || query.Get("bottom_tab_type") != feed.bottomTab {
					t.Errorf("unexpected request: %s %v", request.URL.Path, query)
				}
				offset := query.Get("offset")
				if offset != "0" && (query.Get("session_id") != "fixture-feed" || query.Get("client_req_type") != "2") {
					t.Error("continuation lost the feed session", query)
				}
				offsets = append(offsets, offset)
				cards := []any{
					map[string]any{"show_type": 571, "user_research": map[string]any{}},
					map[string]any{"group_id_type": 27, "video_data": []any{map[string]any{}}},
				}
				for _, id := range pages[offset] {
					row := map[string]any{"series_id": id, "title": "合成推荐 " + id}
					if feed.bottomTab != "" {
						row = map[string]any{"series_id": id, "video_detail": map[string]any{"series_id": id, "series_title": "合成推荐 " + id}}
					}
					cards = append(cards, map[string]any{"group_id_type": 9, "video_data": []any{row}})
				}
				tabType, _ := strconv.Atoi(feed.tabType)
				body, _ := json.Marshal(map[string]any{"code": 0, "data": map[string]any{"tab_item": []any{
					map[string]any{"tab_type": 45, "title": "其他"},
					map[string]any{"tab_type": tabType, "session_id": "fixture-feed", "cell_data": []any{map[string]any{"cell_data": cards}}},
				}}})
				return sourceFixtureResponse(request, http.StatusOK, string(body)), nil
			})
			engine := sourceFixtureEngine(t, transport)
			first, err := engine.nativeRecommendations(context.Background(), nativeInput{Category: feed.key})
			if err != nil || len(first.Items) != 2 || !first.HasMore || first.Items[0].Title != "合成推荐 9001" {
				t.Fatal("first feed page was not parsed", err, first.Items)
			}
			more, err := engine.nativeRecommendations(context.Background(), nativeInput{Category: feed.key, Command: "more"})
			if err != nil || len(more.Items) != 3 || more.Items[2].Title != "合成推荐 9003" {
				t.Fatal("continuation did not skip the repeated page", err, more.Items)
			}
			if !reflect.DeepEqual(offsets, []string{"0", "1", "2"}) {
				t.Fatal("feed offsets did not advance by page", offsets)
			}
		})
	}
}
