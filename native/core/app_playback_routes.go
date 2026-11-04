package core

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"io"
	"net/http"
	"sort"
	"sync"
	"time"
)

// 播放线路测速相关参数。
// 探测只读取媒体地址的前 1KB，用于估算线路的首字节延迟（TTFB），
// 结果在内存里缓存，用于让同一清晰度下的多条线路按快慢排序。
const (
	routeLatencyTTL       = 30 * time.Minute
	routeProbeTimeout     = 3 * time.Second
	routeProbeBudget      = 900 * time.Millisecond
	routeProbeConcurrency = 4
	routeProbeBytes       = 1024
	routeLatencyMaxEntry  = 512
)

type routeLatencyEntry struct {
	rtt      time.Duration
	measured time.Time
}

func nativeRouteKey(media providerMedia) string {
	return media.URL + "\x00" + media.Referer
}

// routeLatency 返回线路的缓存延迟，未测量或已过期时返回 false。
func (engine *nativeEngine) routeLatency(key string) (time.Duration, bool) {
	if engine == nil || key == "" {
		return 0, false
	}
	engine.routeLatencyMu.Lock()
	defer engine.routeLatencyMu.Unlock()
	entry, ok := engine.routeLatencies[key]
	if !ok || entry.rtt <= 0 || time.Since(entry.measured) > routeLatencyTTL {
		return 0, false
	}
	return entry.rtt, true
}

// recordRouteLatency 写入线路延迟，与历史值做加权平滑，避免单次抖动导致来回切换。
func (engine *nativeEngine) recordRouteLatency(key string, rtt time.Duration) {
	if engine == nil || key == "" || rtt <= 0 {
		return
	}
	engine.routeLatencyMu.Lock()
	defer engine.routeLatencyMu.Unlock()
	if engine.routeLatencies == nil {
		engine.routeLatencies = map[string]routeLatencyEntry{}
	}
	if previous, ok := engine.routeLatencies[key]; ok && previous.rtt > 0 && time.Since(previous.measured) <= routeLatencyTTL {
		rtt = (previous.rtt*2 + rtt) / 3
	}
	engine.routeLatencies[key] = routeLatencyEntry{rtt: rtt, measured: time.Now()}
	if len(engine.routeLatencies) > routeLatencyMaxEntry {
		cutoff := time.Now().Add(-routeLatencyTTL)
		for old, entry := range engine.routeLatencies {
			if entry.measured.Before(cutoff) {
				delete(engine.routeLatencies, old)
			}
		}
	}
}

// measureRoute 读取媒体地址的前 1KB，返回耗时；失败返回 0。
// 探测使用独立轻量请求，不经过限流器的 observe：CDN 对探测返回的 403/429
// 不应被记成主机退避，否则会误伤正常的目录与播放请求。
func (engine *nativeEngine) measureRoute(ctx context.Context, media providerMedia, timeout time.Duration) time.Duration {
	if engine == nil || engine.downloader == nil || !isProviderHTTPMediaURL(media.URL) {
		return 0
	}
	probeCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	request, err := http.NewRequestWithContext(probeCtx, http.MethodGet, media.URL, nil)
	if err != nil {
		return 0
	}
	mediaRequestHeaders(request, media.Referer)
	request.Header.Set("Range", "bytes=0-1023")
	if media.credentials != nil {
		if err := media.credentials.apply(request); err != nil {
			return 0
		}
	}
	client := *engine.downloader.client
	client.Timeout = timeout
	client.Jar = nil
	start := time.Now()
	response, err := client.Do(request)
	if err != nil {
		return 0
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, routeProbeBytes))
	elapsed := time.Since(start)
	if response.StatusCode >= http.StatusBadRequest && response.StatusCode != http.StatusRequestedRangeNotSatisfiable {
		return 0
	}
	return elapsed
}

// probeRoutes 并发探测尚未测量的线路。
// 只探测与首选线路同一清晰度的线路，避免为用不上的清晰度白白发请求。
// budget > 0 时最多等待 budget，超时后探测继续在后台完成（结果供下一次使用）。
func (engine *nativeEngine) probeRoutes(choice nativePlaybackChoice, budget time.Duration) {
	if engine == nil || len(choice.media) < 2 {
		return
	}
	quality := choice.media[0].Quality
	pending := make([]providerMedia, 0, len(choice.media))
	for _, media := range choice.media {
		if media.Quality != quality {
			continue
		}
		if _, ok := engine.routeLatency(nativeRouteKey(media)); ok {
			continue
		}
		pending = append(pending, media)
	}
	if len(pending) == 0 {
		return
	}
	ctx := context.Background()
	semaphore := make(chan struct{}, routeProbeConcurrency)
	var waiter sync.WaitGroup
	for _, media := range pending {
		waiter.Add(1)
		go func(media providerMedia) {
			defer waiter.Done()
			semaphore <- struct{}{}
			defer func() { <-semaphore }()
			if rtt := engine.measureRoute(ctx, media, routeProbeTimeout); rtt > 0 {
				engine.recordRouteLatency(nativeRouteKey(media), rtt)
			}
		}(media)
	}
	if budget <= 0 {
		waiter.Wait()
		return
	}
	done := make(chan struct{})
	go func() {
		waiter.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(budget):
	}
}

// nativeRankRoutes 在同一清晰度内按已测得的延迟把快的线路排到前面。
// 只有存在缓存数据时才会改变顺序，保证没有测速结果时行为与原来完全一致。
func (engine *nativeEngine) nativeRankRoutes(choice *nativePlaybackChoice) {
	if engine == nil || choice == nil || len(choice.media) < 2 {
		return
	}
	latency := make([]time.Duration, len(choice.media))
	known := false
	for index, media := range choice.media {
		if value, ok := engine.routeLatency(nativeRouteKey(media)); ok {
			latency[index] = value
			known = true
		} else {
			latency[index] = 0
		}
	}
	if !known {
		return
	}
	order := make([]int, len(choice.media))
	for index := range order {
		order[index] = index
	}
	sort.SliceStable(order, func(i, j int) bool {
		left, right := choice.media[order[i]], choice.media[order[j]]
		if left.Quality != right.Quality {
			return left.Quality > right.Quality
		}
		leftLatency, rightLatency := latency[order[i]], latency[order[j]]
		if leftLatency == 0 || rightLatency == 0 {
			// 未测速的线路保持原有相对位置，只把已测出更快的线路提前。
			return leftLatency > 0 && rightLatency == 0
		}
		return leftLatency < rightLatency
	})
	ranked := make([]providerMedia, 0, len(choice.media))
	for _, index := range order {
		ranked = append(ranked, choice.media[index])
	}
	choice.media = ranked
}

type nativePlaybackChoice struct {
	danmakuSeries string
	danmakuVideo  string
	media         []providerMedia
	index         int
	qualities     []int
	streamSession string
	created       time.Time
}

func nativePlaybackChoices(media providerMedia, quality int) nativePlaybackChoice {
	choice := nativePlaybackChoice{qualities: []int{}}
	seen := map[string]bool{}
	qualities := map[int]bool{}
	for _, option := range append([]providerMedia{media}, media.Variants...) {
		if !isProviderHTTPMediaURL(option.URL) {
			continue
		}
		identity := option.URL + "\x00" + option.Referer + "\x00" + hex.EncodeToString(option.CENCKey) + "\x00" + hex.EncodeToString(option.HLSKey)
		if seen[identity] {
			continue
		}
		seen[identity] = true
		option.Variants = nil
		choice.media = append(choice.media, option)
		if option.Quality > 0 {
			qualities[option.Quality] = true
		}
	}
	sort.SliceStable(choice.media, func(i, j int) bool { return choice.media[i].Quality > choice.media[j].Quality })
	for value := range qualities {
		choice.qualities = append(choice.qualities, value)
	}
	sort.Sort(sort.Reverse(sort.IntSlice(choice.qualities)))
	if quality > 0 && qualities[quality] {
		filtered := make([]providerMedia, 0, len(choice.media))
		for _, option := range choice.media {
			if option.Quality == quality {
				filtered = append(filtered, option)
			}
		}
		choice.media = filtered
	}
	return choice
}

func (engine *nativeEngine) nativeOpenPlayback(ctx context.Context, choice nativePlaybackChoice) (nativePlan, error) {
	if err := ctx.Err(); err != nil {
		return nativePlan{}, err
	}
	if choice.index < 0 || choice.index >= len(choice.media) {
		return nativePlan{}, errors.New("该集没有其他可用的播放线路")
	}
	media := choice.media[choice.index]
	var err error
	if !isProviderHTTPMediaURL(media.URL) {
		return nativePlan{}, errors.New("站源未返回有效的播放地址")
	}
	tokenBytes := make([]byte, 24)
	if _, err := rand.Read(tokenBytes); err != nil {
		return nativePlan{}, errors.New("无法初始化播放会话")
	}
	plan := nativePlan{
		DanmakuID: choice.danmakuVideo,
		URL:       media.URL, Headers: map[string]string{"User-Agent": userAgent, "Referer": media.Referer},
		Key: hex.EncodeToString(media.CENCKey), Quality: media.Quality, Qualities: choice.qualities,
		RouteIndex: choice.index, RouteCount: len(choice.media), Session: hex.EncodeToString(tokenBytes),
	}
	if media.credentials != nil && !media.credentials.expires.IsZero() {
		if !time.Now().Before(media.credentials.expires) {
			return nativePlan{}, errors.New("播放凭证已过期，请重新解析播放")
		}
		plan.ExpiresAt = media.credentials.expires.UnixMilli()
	}
	choice.streamSession = ""
	{
		engine.mu.Lock()
		if engine.stream == nil {
			engine.stream, err = newNativeStreamServer(engine.downloader)
		}
		stream := engine.stream
		engine.mu.Unlock()
		if err != nil {
			return nativePlan{}, err
		}
		plan.URL, choice.streamSession = stream.nativeOpen(media)
	}
	choice.created = time.Now()
	engine.mu.Lock()
	if engine.playbacks == nil {
		engine.playbacks = map[string]nativePlaybackChoice{}
	}
	var expired []string
	for token, old := range engine.playbacks {
		if time.Since(old.created) > 12*time.Hour {
			expired = append(expired, old.streamSession)
			delete(engine.playbacks, token)
		}
	}
	if len(engine.playbacks) >= 8 {
		oldest := ""
		for token, old := range engine.playbacks {
			if oldest == "" || old.created.Before(engine.playbacks[oldest].created) {
				oldest = token
			}
		}
		expired = append(expired, engine.playbacks[oldest].streamSession)
		delete(engine.playbacks, oldest)
	}
	engine.playbacks[plan.Session] = choice
	stream := engine.stream
	engine.mu.Unlock()
	if stream != nil {
		for _, token := range expired {
			stream.nativeRelease(token)
		}
	}
	if err := ctx.Err(); err != nil {
		engine.nativeReleasePlayback(plan.Session)
		return nativePlan{}, err
	}
	return plan, nil
}

func (engine *nativeEngine) nativeNextPlayback(ctx context.Context, session string) (nativePlan, error) {
	engine.mu.Lock()
	choice, exists := engine.playbacks[session]
	engine.mu.Unlock()
	if !exists {
		return nativePlan{}, errors.New("播放线路已失效，请重新解析播放")
	}
	choice.index++
	if choice.index < len(choice.media) {
		// 已测得延迟时，直接切到剩余线路中最快的一条，避免逐条试错。
		best, bestLatency := choice.index, time.Duration(0)
		if value, ok := engine.routeLatency(nativeRouteKey(choice.media[best])); ok {
			bestLatency = value
		}
		for index := choice.index + 1; index < len(choice.media); index++ {
			value, ok := engine.routeLatency(nativeRouteKey(choice.media[index]))
			if !ok {
				continue
			}
			if bestLatency <= 0 || value < bestLatency {
				best, bestLatency = index, value
			}
		}
		choice.index = best
	}
	return engine.nativeOpenPlayback(ctx, choice)
}

func (engine *nativeEngine) nativeReleasePlayback(session string) {
	engine.mu.Lock()
	choice, exists := engine.playbacks[session]
	delete(engine.playbacks, session)
	stream := engine.stream
	engine.mu.Unlock()
	if exists && stream != nil && choice.streamSession != "" {
		stream.nativeRelease(choice.streamSession)
	}
}
