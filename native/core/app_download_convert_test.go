package core

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func copyConversion(t *testing.T, manager *nativeDownloads, work nativeDownloadConversion, id string) {
	t.Helper()
	data, err := os.ReadFile(work.Input)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(work.Output, data, 0600); err != nil {
		t.Fatal(err)
	}
	if err := manager.finishConversion(id, "done"); err != nil {
		t.Fatal(err)
	}
}

func convertingFixture(t *testing.T, manager *nativeDownloads, drama nativeDrama, index int, bySource bool) string {
	t.Helper()
	id := nativeDownloadID(drama.ID, index)
	record := &nativeDownloadRecord{nativeDownloadJob: nativeDownloadJob{ID: id, Index: index, Drama: drama,
		State: "converting", Bytes: 15, Progress: 1}, File: "media.mp4", Key: "00112233445566778899aabbccddeeff"}
	if bySource {
		record.Folder = drama.Source + "/" + id
	}
	directory := manager.jobDirectory(record.nativeDownloadJob)
	if err := os.MkdirAll(directory, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "media.mp4"), []byte("synthetic-video"), 0600); err != nil {
		t.Fatal(err)
	}
	manager.mu.Lock()
	defer manager.mu.Unlock()
	manager.jobs[id] = record
	if err := manager.saveLocked(); err != nil {
		t.Fatal(err)
	}
	return id
}

func convertFixture(t *testing.T, manager *nativeDownloads, id string) string {
	t.Helper()
	work, err := manager.beginConversion(id)
	if err != nil {
		t.Fatal(err)
	}
	copyConversion(t, manager, work, id)
	manager.mu.Lock()
	defer manager.mu.Unlock()
	record := manager.jobs[id]
	if record.State != "completed" || record.File != "" || record.Key != "" || record.Bytes != 15 {
		t.Fatalf("conversion not recorded: %+v", record)
	}
	return record.Output
}

func TestNativeDownloadConversionNamesFoldersByDrama(t *testing.T) {
	manager := downloadTestManager(t)
	first := nativeDrama{ID: "hongguo:801", Source: "hongguo", Title: " 甲:剧/名? "}
	twin := nativeDrama{ID: "hongguo:802", Source: "hongguo", Title: "甲:剧/名?"}
	device := nativeDrama{ID: "hongguo:803", Source: "hongguo", Title: "con.剧"}
	one := convertingFixture(t, manager, first, 1, false)
	two := convertingFixture(t, manager, first, 2, false)
	other := convertingFixture(t, manager, twin, 1, false)
	sourced := convertingFixture(t, manager, device, 3, true)
	for id, want := range map[string]string{one: "甲_剧_名_/第1集.mp4", two: "甲_剧_名_/第2集.mp4"} {
		if got := convertFixture(t, manager, id); got != want {
			t.Fatalf("output %q, want %q", got, want)
		}
	}
	if got := convertFixture(t, manager, other); got != "甲_剧_名_ (2)/第1集.mp4" {
		t.Fatalf("same title must not share folders: %q", got)
	}
	if got := convertFixture(t, manager, sourced); got != "hongguo/_con.剧/第3集.mp4" {
		t.Fatalf("reserved or source folder: %q", got)
	}
	if _, err := os.Stat(filepath.Join(manager.root, "hongguo", sourced)); !os.IsNotExist(err) {
		t.Fatal("source workspace kept")
	}
	manager.close()
	reopened := newNativeDownloads(manager.engine)
	t.Cleanup(reopened.close)
	if reopened.loadErr != nil || len(reopened.jobs) != 4 {
		t.Fatalf("converted records not reloaded: %v", reopened.loadErr)
	}
	folder := filepath.Join(reopened.root, "甲_剧_名_")
	if err := reopened.control(one, "remove"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(folder, "第2集.mp4")); err != nil {
		t.Fatal("removing one episode touched another")
	}
	if err := reopened.control(two, "remove"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(folder); !os.IsNotExist(err) {
		t.Fatal("empty drama folder kept")
	}
}

func TestNativeDownloadConversionRejectsUnsafeOutput(t *testing.T) {
	manager := downloadTestManager(t)
	drama := nativeDrama{ID: "hongguo:804", Source: "hongguo", Title: "样本"}
	id := nativeDownloadID(drama.ID, 1)
	for _, output := range []string{"../样本/第1集.mp4", "样本/第2集.mp4", "huangdou/样本/第1集.mp4", "a/b/c/第1集.mp4", "样本./第1集.mp4", "NUL/第1集.mp4"} {
		records := []nativeDownloadRecord{{nativeDownloadJob: nativeDownloadJob{ID: id, Index: 1, Drama: drama,
			State: "completed", Bytes: 15}, Output: output}}
		data, _ := json.Marshal(records)
		if err := os.WriteFile(filepath.Join(manager.root, "index.json"), data, 0600); err != nil {
			t.Fatal(err)
		}
		reopened := newNativeDownloads(manager.engine)
		reopened.close()
		if reopened.loadErr == nil {
			t.Fatalf("unsafe output accepted: %s", output)
		}
	}
}

func TestNativeDownloadConversionFailureRetryAndRemoval(t *testing.T) {
	manager := downloadTestManager(t)
	drama := nativeDrama{ID: "hongguo:805", Source: "hongguo", Title: "样本"}
	id := convertingFixture(t, manager, drama, 1, false)
	if _, found, err := manager.localPlan(drama.ID, 1); found || err != nil {
		t.Fatal("converting episode must fall back to online playback")
	}
	if _, err := manager.beginConversion(id); err != nil {
		t.Fatal(err)
	}
	if count, err := manager.engine.workLease("", ""); err != nil || count != 1 {
		t.Fatalf("background service cannot see the running conversion: %d %v", count, err)
	}
	if _, err := manager.beginConversion(id); err == nil {
		t.Fatal("same episode converted twice")
	}
	if err := manager.engine.moveDownloads(context.Background(), t.TempDir()); err == nil || !strings.Contains(err.Error(), "处理完成") {
		t.Fatal("download folder moved during conversion")
	}
	if err := manager.finishConversion(id, "failed"); err != nil {
		t.Fatal(err)
	}
	jobs, _ := manager.snapshot()
	if len(jobs) != 1 || jobs[0].State != "failed" || jobs[0].Error != "转换失败，点击重试" {
		t.Fatalf("failure not recorded: %+v", jobs)
	}
	if count, _ := manager.engine.workLease("", ""); count != 0 {
		t.Fatalf("finished conversion still keeps the service alive: %d", count)
	}
	if err := manager.control(id, "resume"); err != nil {
		t.Fatal(err)
	}
	if jobs, _ = manager.snapshot(); jobs[0].State != "converting" {
		t.Fatalf("retry must convert again without downloading: %+v", jobs)
	}
	work, err := manager.beginConversion(id)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(work.Output, []byte("partial"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := manager.control(id, "remove"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(work.Input); err != nil {
		t.Fatal("files removed while conversion was still running")
	}
	if err := manager.finishConversion(id, "cancel"); err != nil {
		t.Fatal(err)
	}
	if jobs, _ = manager.snapshot(); len(jobs) != 0 {
		t.Fatalf("removed episode kept: %+v", jobs)
	}
	if _, err := os.Stat(filepath.Dir(work.Input)); !os.IsNotExist(err) {
		t.Fatal("removed episode files kept")
	}
	broken := convertingFixture(t, manager, drama, 2, false)
	if err := os.Remove(filepath.Join(manager.root, broken, "media.mp4")); err != nil {
		t.Fatal(err)
	}
	if _, err := manager.beginConversion(broken); err == nil {
		t.Fatal("missing download converted")
	}
	manager.resolve = func(ctx context.Context, job nativeDownloadJob) (providerMedia, error) {
		<-ctx.Done()
		return providerMedia{}, ctx.Err()
	}
	if err := manager.control(broken, "resume"); err != nil {
		t.Fatal(err)
	}
	if jobs, _ = manager.snapshot(); len(jobs) != 1 || jobs[0].State != "downloading" {
		t.Fatalf("missing download must be fetched again: %+v", jobs)
	}
}
