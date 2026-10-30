package core

import "testing"

func TestHuangguoAIReleaseStatusFromFinishedFlag(t *testing.T) {
	for flag, want := range map[any]string{true: "finished", false: "ongoing", "1": "finished", "0": "ongoing"} {
		drama, ok := dramaFromAIMap(map[string]any{"id": "a1", "title": "示例剧", "total_episodes": float64(12), "is_finished": flag}, huangguoAIBaseURL, "")
		if !ok || drama.ReleaseStatus != want {
			t.Fatalf("is_finished=%v: got %q, %v", flag, drama.ReleaseStatus, ok)
		}
	}
	drama, _ := dramaFromAIMap(map[string]any{"id": "a2", "title": "示例剧"}, huangguoAIBaseURL, "")
	if drama.ReleaseStatus != "" {
		t.Fatalf("missing flag: got %q", drama.ReleaseStatus)
	}
}

func TestHuangguoVideoCardReleaseStatusFromMetaLine(t *testing.T) {
	page := `<article class="video-card"><a href="/series/s1"><img alt="示例剧一" src="/a.jpg"><span class="absolute font-mono-meta cover-pill-text">更新至第12集</span></a><p class="mt-2.5 font-card-title">示例剧一</p><p class="mt-2 text-[11px] font-mono-meta">连续剧 · 已完结 · 30 次下载</p></article>` +
		`<article class="video-card"><a href="/series/s2"><img alt="示例剧二" src="/b.jpg"><span class="absolute font-mono-meta cover-pill-text">更新至第3集</span></a><p class="mt-2 text-[11px] font-mono-meta">连续剧 · 连载中</p></article>` +
		`<article class="video-card"><a href="/video/v1"><img alt="示例短片" src="/c.jpg"><span class="absolute font-mono-meta cover-pill-text">03:20</span></a><p class="mt-2 text-[11px] font-mono-meta">短片 · 03:20</p></article>`
	want := map[string]string{"series/s1": "finished", "series/s2": "ongoing", "video/v1": ""}
	cards := parseHuangguoVideoCards(page, huangguoVideoBaseURL+"/videos")
	if len(cards) != len(want) {
		t.Fatalf("cards = %d", len(cards))
	}
	for _, card := range cards {
		if card.ReleaseStatus != want[card.SourceID] {
			t.Fatalf("%s: got %q", card.SourceID, card.ReleaseStatus)
		}
	}
}

func TestHuangguoVideoDetailReleaseStatusFromHeader(t *testing.T) {
	page := `<main><p class="font-mono-meta text-[10px] uppercase">连续剧</p><h1 class="font-display">示例剧</h1><p class="mt-2 text-sm text-mist-dim font-mono-meta">已完结 · 12 集</p>` +
		`<div class="vcard-meta"><div class="vcard-title">推荐剧</div><span>连载中</span></div></main>`
	if got := huangguoDetailMetadata(page, huangguoVideoBaseURL+"/series/s1", sourceHuangguoVideo, "series/s1").ReleaseStatus; got != "finished" {
		t.Fatalf("series detail: got %q", got)
	}
	if got := huangguoDetailMetadata(page, huangguoVideoBaseURL+"/video/v1", sourceHuangguoVideo, "video/v1").ReleaseStatus; got != "unknown" {
		t.Fatalf("video detail: got %q", got)
	}
}
