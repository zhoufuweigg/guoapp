package core

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

const (
	hongguoBookmallTabPath        = "/reading/bookapi/bookmall/tab/v1/"
	hongguoBookmallCellChangePath = "/reading/bookapi/bookmall/cell/change/v1/"
	hongguoDoubleColFeedShowType  = "506"
	hongguoCellPageSize           = 6
)

var hongguoRecommendationFeeds = []struct {
	key       string
	tabType   string
	bottomTab string
}{
	{key: "home_feed", tabType: "16", bottomTab: "7"},
	{key: "find_drama", tabType: "8"},
}

type hongguoRecommendationQuery struct {
	Genre     string   `json:"genre"`
	Offset    int      `json:"offset"`
	SessionID string   `json:"sessionId"`
	CellID    string   `json:"cellId,omitempty"`
	ShowType  string   `json:"showType,omitempty"`
	Seen      []string `json:"seen"`
}

type hongguoRecommendationPage struct {
	Dramas     []Drama `json:"data"`
	NextOffset int     `json:"nextOffset"`
	SessionID  string  `json:"sessionId"`
	CellID     string  `json:"cellId,omitempty"`
	ShowType   string  `json:"showType,omitempty"`
	HasMore    bool    `json:"hasMore"`
	Saved      bool    `json:"saved"`
}

func (query hongguoRecommendationQuery) validate() error {
	known := false
	for _, genre := range hongguoAppGenres {
		known = known || query.Genre == genre.key
	}
	for _, feed := range hongguoRecommendationFeeds {
		known = known || query.Genre == feed.key
	}
	if !known || query.Offset < 0 || query.Offset > 1_000_000 || len(query.SessionID) > 4096 || strings.ContainsAny(query.SessionID, "\r\n\x00") || len(query.Seen) > 540 ||
		query.CellID != "" && !hongguoNumericID.MatchString(query.CellID) || query.ShowType != "" && !hongguoNumericID.MatchString(query.ShowType) {
		return errors.New("推荐分类或分页参数无效，请重新获取")
	}
	for _, id := range query.Seen {
		if !hongguoNumericID.MatchString(strings.TrimPrefix(id, "hongguo:")) {
			return errors.New("推荐分页含无效剧集 ID")
		}
	}
	return nil
}

func (downloader *Downloader) fetchHongguoRecommendations(ctx context.Context, query hongguoRecommendationQuery) (hongguoRecommendationPage, error) {
	page := hongguoRecommendationPage{Dramas: []Drama{}}
	if err := query.validate(); err != nil {
		return page, err
	}
	for _, feed := range hongguoRecommendationFeeds {
		if feed.key == query.Genre {
			return downloader.fetchHongguoFeedRecommendations(ctx, query, feed.tabType, feed.bottomTab)
		}
	}
	scene, category := "", ""
	for _, genre := range hongguoAppGenres {
		if genre.key == query.Genre {
			scene, category = genre.scene, genre.name
		}
	}
	seen := make(map[string]bool, len(query.Seen))
	filterIDs := make([]string, 0, len(query.Seen))
	for _, id := range query.Seen {
		id = strings.TrimPrefix(id, "hongguo:")
		if !seen[id] {
			filterIDs = append(filterIDs, id)
			seen[id] = true
		}
	}
	payload := map[string]any{
		"req_scene": scene, "offset": query.Offset, "limit": 54,
		"req_type": "only_content", "need_selector_panel": false, "client_req_type": 3,
		"session_id": query.SessionID, "filter_ids": strings.Join(filterIDs, ","),
		"select_items": map[string]any{
			"genre": []string{query.Genre}, "sort": []string{}, "gender": []string{},
			"category_dim_theme": []string{}, "category_dim_role": []string{}, "category_dim_epoch": []string{},
			"online_time": []string{}, "creation_status": []string{},
		},
	}
	if query.Offset > 0 {
		payload["client_req_type"] = 2
	}
	result, err := downloader.hongguoAppRequest(ctx, http.MethodPost, "/reading/distribution/category/landpage/v/", nil, payload)
	if err != nil {
		return page, err
	}
	data := nestedMap(result, "data")
	rows, valid := data["video_data"].([]any)
	hasMore, paginationOK := data["has_more"].(bool)
	next, parseErr := strconv.Atoi(mapString(data, "next_offset"))
	if !valid || !paginationOK || hasMore && parseErr != nil {
		return page, errors.New("红果推荐数据格式异常，已保留上次位置")
	}
	validRows := 0
	for _, row := range rows {
		drama := hongguoDramaFromAny(row, category)
		if drama.ID != "" {
			validRows++
		}
		id := strings.TrimPrefix(drama.ID, "hongguo:")
		if drama.ID == "" || seen[id] {
			continue
		}
		seen[id] = true
		page.Dramas = append(page.Dramas, drama)
	}
	if len(rows) > 0 && validRows == 0 {
		return hongguoRecommendationPage{}, errors.New("红果推荐未返回可识别的剧集")
	}
	if hasMore && (next <= query.Offset || next > 1_000_000 || len(page.Dramas) == 0) {
		return hongguoRecommendationPage{}, errors.New("红果推荐分页未前进，可重试或重新获取")
	}
	page.NextOffset, page.HasMore, page.SessionID = next, hasMore, mapString(data, "session_id")
	if !hasMore && (next < query.Offset || next > 1_000_000) {
		page.NextOffset = query.Offset
	}
	if len(page.SessionID) > 4096 || strings.ContainsAny(page.SessionID, "\r\n\x00") {
		return hongguoRecommendationPage{}, errors.New("红果推荐分页标记无效")
	}
	return page, ctx.Err()
}

type hongguoCellPage struct {
	cards   []any
	next    int
	hasMore bool
	session string
}

func (downloader *Downloader) fetchHongguoCellPage(ctx context.Context, page hongguoRecommendationPage, tabType string, offset int) (hongguoCellPage, error) {
	extra := url.Values{
		"cell_id": {page.CellID}, "change_type": {"0"}, "offset": {strconv.Itoa(offset)}, "limit": {"10"},
		"session_id": {page.SessionID}, "tab_type": {tabType}, "client_req_type": {"2"}, "show_type": {page.ShowType},
	}
	result, err := downloader.hongguoAppRequest(ctx, http.MethodGet, hongguoBookmallCellChangePath, extra, nil)
	if err != nil {
		return hongguoCellPage{}, err
	}
	data := nestedMap(result, "data")
	hasMore, paginationOK := data["has_more"].(bool)
	next, parseErr := strconv.Atoi(mapString(data, "next_offset"))
	if !paginationOK || hasMore && (parseErr != nil || next <= offset) {
		return hongguoCellPage{}, errors.New("红果推荐数据格式异常，已保留上次位置")
	}
	return hongguoCellPage{cards: anyList(nestedMap(data, "cell_view")["cell_data"]), next: next, hasMore: hasMore, session: mapString(data, "session_id")}, nil
}

func (downloader *Downloader) fetchHongguoFeedRecommendations(ctx context.Context, query hongguoRecommendationQuery, tabType, bottomTab string) (hongguoRecommendationPage, error) {
	seen := make(map[string]bool, len(query.Seen))
	for _, id := range query.Seen {
		seen[strings.TrimPrefix(id, "hongguo:")] = true
	}
	page := hongguoRecommendationPage{Dramas: []Drama{}, NextOffset: query.Offset, SessionID: query.SessionID, CellID: query.CellID, ShowType: query.ShowType, HasMore: true}
	validRows := 0
	for attempt := 0; attempt < 3 && len(page.Dramas) == 0 && page.HasMore; attempt++ {
		var cards []any
		if page.CellID != "" {
			helperOffset := page.NextOffset + hongguoCellPageSize
			var helperPage hongguoCellPage
			var helperErr error
			helperDone := make(chan struct{})
			go func(page hongguoRecommendationPage) {
				defer close(helperDone)
				helperPage, helperErr = downloader.fetchHongguoCellPage(context.WithValue(ctx, hongguoHelperDeviceKey{}, true), page, tabType, helperOffset)
			}(page)
			primary, err := downloader.fetchHongguoCellPage(ctx, page, tabType, page.NextOffset)
			<-helperDone
			if err != nil {
				return hongguoRecommendationPage{}, err
			}
			cards = primary.cards
			page.HasMore, page.SessionID = primary.hasMore, firstNonEmpty(primary.session, page.SessionID)
			if primary.hasMore {
				page.NextOffset = primary.next
			}
			if helperErr == nil && primary.hasMore && primary.next == helperOffset {
				cards = append(cards, helperPage.cards...)
				page.HasMore = helperPage.hasMore
				if helperPage.hasMore {
					page.NextOffset = helperPage.next
				}
			}
		} else {
			extra := url.Values{"tab_type": {tabType}, "offset": {strconv.Itoa(page.NextOffset)}, "client_req_type": {"1"}}
			if bottomTab != "" {
				extra.Set("bottom_tab_type", bottomTab)
				extra.Set("landing_bottom_tab_type", bottomTab)
			}
			if page.SessionID != "" {
				extra.Set("session_id", page.SessionID)
				extra.Set("client_req_type", "2")
			}
			result, err := downloader.hongguoAppRequest(ctx, http.MethodGet, hongguoBookmallTabPath, extra, nil)
			if err != nil {
				return hongguoRecommendationPage{}, err
			}
			var tab map[string]any
			for _, item := range anyList(nestedMap(result, "data")["tab_item"]) {
				if row, _ := item.(map[string]any); mapString(row, "tab_type") == tabType {
					tab = row
				}
			}
			if tab == nil {
				return hongguoRecommendationPage{}, errors.New("红果推荐数据格式异常，已保留上次位置")
			}
			if page.SessionID == "" {
				page.SessionID = mapString(tab, "session_id")
			}
			page.NextOffset++
			for _, cell := range anyList(tab["cell_data"]) {
				cellMap, _ := cell.(map[string]any)
				cards = append(cards, anyList(cellMap["cell_data"])...)
				id, next := mapString(cellMap, "cell_id"), mapString(cellMap, "next_offset")
				if offset, err := strconv.Atoi(next); err == nil && offset > 0 && mapString(cellMap, "show_type") == hongguoDoubleColFeedShowType && hongguoNumericID.MatchString(id) {
					page.CellID, page.ShowType, page.NextOffset = id, hongguoDoubleColFeedShowType, offset
				}
			}
		}
		for _, card := range cards {
			cardMap, _ := card.(map[string]any)
			for _, video := range anyList(cardMap["video_data"]) {
				row, _ := video.(map[string]any)
				if detail, _ := row["video_detail"].(map[string]any); len(detail) > 0 {
					row = detail
				}
				drama := hongguoDramaFromAny(row, "")
				if drama.ID == "" {
					continue
				}
				validRows++
				if id := strings.TrimPrefix(drama.ID, "hongguo:"); !seen[id] {
					seen[id] = true
					page.Dramas = append(page.Dramas, drama)
				}
			}
		}
	}
	if len(page.SessionID) > 4096 || strings.ContainsAny(page.SessionID, "\r\n\x00") {
		return hongguoRecommendationPage{}, errors.New("红果推荐分页标记无效")
	}
	if !page.HasMore {
		return page, ctx.Err()
	}
	if validRows == 0 {
		return hongguoRecommendationPage{}, errors.New("红果推荐未返回可识别的剧集")
	}
	if len(page.Dramas) == 0 || page.NextOffset > 1_000_000 {
		return hongguoRecommendationPage{}, errors.New("红果推荐分页未前进，可重试或重新获取")
	}
	return page, ctx.Err()
}
