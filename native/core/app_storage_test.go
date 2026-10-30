package core

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func storageFixture(t *testing.T) (*nativeEngine, string) {
	t.Helper()
	engine, err := newNativeEngine(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	id := nativeDownloadID("hongguo:70001", 1)
	manager := engine.downloads
	if err := os.MkdirAll(filepath.Join(manager.root, id), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(manager.root, id, "media.mp4"), []byte("synthetic-video"), 0600); err != nil {
		t.Fatal(err)
	}
	manager.jobs[id] = &nativeDownloadRecord{nativeDownloadJob: nativeDownloadJob{
		ID: id, Index: 1, Drama: nativeDrama{ID: "hongguo:70001", Source: "hongguo"},
		State: "completed", Bytes: 15}, File: "media.mp4"}
	if err := manager.saveLocked(); err != nil {
		t.Fatal(err)
	}
	return engine, id
}

func TestDownloadMigrationPreservesMediaAndRestartLocation(t *testing.T) {
	engine, id := storageFixture(t)
	old := engine.downloads.root
	target := t.TempDir()
	if err := engine.moveDownloads(context.Background(), target); err != nil {
		t.Fatal(err)
	}
	location := nativeDownloadLocation(engine.directory, engine.defaultDownloads)
	if location != engine.downloads.root || location == old {
		t.Fatal("new location was not persisted")
	}
	if _, err := os.Stat(old); !os.IsNotExist(err) {
		t.Fatal("old media not cleaned after successful migration")
	}
	if body, err := os.ReadFile(filepath.Join(location, id, "media.mp4")); err != nil || string(body) != "synthetic-video" {
		t.Fatalf("media not copied: %v", err)
	}
	info, err := engine.storage()
	if err != nil || info.Files < 2 || info.Bytes < 15 || info.Free < 1 {
		t.Fatalf("storage stats: %+v %v", info, err)
	}
	restarted := newNativeDownloads(engine)
	defer restarted.close()
	if len(restarted.jobs) != 1 || restarted.jobs[id].State != "completed" {
		t.Fatal("restart lost jobs")
	}
}

func TestDownloadMigrationRestoresDefaultLocation(t *testing.T) {
	engine, id := storageFixture(t)
	if info, err := engine.storage(); err != nil || !info.Default {
		t.Fatalf("fresh root not default: %+v %v", info, err)
	}
	if err := engine.moveDownloads(context.Background(), t.TempDir()); err != nil {
		t.Fatal(err)
	}
	moved := engine.downloads.root
	if info, err := engine.storage(); err != nil || info.Default {
		t.Fatalf("moved root reported default: %+v %v", info, err)
	}
	if err := engine.moveDownloads(context.Background(), ""); err != nil {
		t.Fatal(err)
	}
	if engine.downloads.root != engine.defaultDownloads {
		t.Fatal("root not restored")
	}
	if _, err := os.Stat(filepath.Join(engine.directory, "download-location.json")); !os.IsNotExist(err) {
		t.Fatal("location file kept after restore")
	}
	if _, err := os.Stat(moved); !os.IsNotExist(err) {
		t.Fatal("moved media not cleaned after restore")
	}
	if body, err := os.ReadFile(filepath.Join(engine.downloads.root, id, "media.mp4")); err != nil || string(body) != "synthetic-video" {
		t.Fatalf("media not restored: %v", err)
	}
	if info, err := engine.storage(); err != nil || !info.Default {
		t.Fatalf("restored root not default: %+v %v", info, err)
	}
	restarted := newNativeDownloads(engine)
	defer restarted.close()
	if restarted.root != engine.downloads.root || restarted.jobs[id] == nil {
		t.Fatal("restart lost restored location")
	}
}

func TestExternalDefaultDownloadsUsedWhenLegacyEmpty(t *testing.T) {
	directory := t.TempDir()
	external := filepath.Join(t.TempDir(), "downloads")
	if err := os.MkdirAll(nativeDefaultDownloads(directory), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(nativeDefaultDownloads(directory), "index.json"), []byte("[]"), 0600); err != nil {
		t.Fatal(err)
	}
	engine, err := newNativeEngine(directory, external)
	if err != nil {
		t.Fatal(err)
	}
	defer engine.downloads.close()
	if engine.downloads.root != external {
		t.Fatalf("root %q, want %q", engine.downloads.root, external)
	}
	if info, err := engine.storage(); err != nil || !info.Default {
		t.Fatalf("external root not default: %+v %v", info, err)
	}
}

func TestLegacyDownloadsPinnedUntilRestored(t *testing.T) {
	legacy, id := storageFixture(t)
	legacy.downloads.close()
	external := filepath.Join(t.TempDir(), "downloads")
	engine, err := newNativeEngine(legacy.directory, external)
	if err != nil {
		t.Fatal(err)
	}
	defer engine.downloads.close()
	old := nativeDefaultDownloads(legacy.directory)
	if engine.downloads.root != old || engine.downloads.jobs[id] == nil {
		t.Fatal("legacy downloads not kept")
	}
	if info, err := engine.storage(); err != nil || info.Default {
		t.Fatalf("legacy root reported default: %+v %v", info, err)
	}
	if err := engine.moveDownloads(context.Background(), ""); err != nil {
		t.Fatal(err)
	}
	if engine.downloads.root != external {
		t.Fatal("restore did not move to external default")
	}
	if body, err := os.ReadFile(filepath.Join(external, id, "media.mp4")); err != nil || string(body) != "synthetic-video" {
		t.Fatalf("media not moved: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(old, "leftover"), 0700); err != nil {
		t.Fatal(err)
	}
	if location := nativeDownloadLocation(legacy.directory, external); location != external {
		t.Fatalf("unexpected location %q", location)
	}
}

func TestMigrationFailureLeavesSourceAndExistingTargetIntact(t *testing.T) {
	engine, _ := storageFixture(t)
	old := engine.downloads.root
	parent := t.TempDir()
	existing := filepath.Join(parent, "zhenguojian-downloads")
	os.Mkdir(existing, 0700)
	os.WriteFile(filepath.Join(existing, "user-file"), []byte("keep"), 0600)
	if err := engine.moveDownloads(context.Background(), parent); err == nil {
		t.Fatal("existing directory overwritten")
	}
	if _, err := os.Stat(filepath.Join(existing, "user-file")); err != nil {
		t.Fatal("existing content removed")
	}
	if engine.downloads.root != old {
		t.Fatal("failed migration changed root")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	empty := t.TempDir()
	if err := engine.moveDownloads(ctx, empty); err == nil {
		t.Fatal("cancelled migration succeeded")
	}
	if _, err := os.Stat(old); err != nil {
		t.Fatal("source removed after cancellation")
	}
	if _, err := os.Stat(filepath.Join(empty, "zhenguojian-downloads")); !os.IsNotExist(err) {
		t.Fatal("partial target not cleaned")
	}
}

func TestStorageLeaseRejectsParallelAndRetiredTasks(t *testing.T) {
	engine, _ := storageFixture(t)
	if count, err := engine.workLease("storage", "start"); err != nil || count != 1 {
		t.Fatalf("start: %d %v", count, err)
	}
	if _, err := engine.workLease("storage", "start"); err == nil {
		t.Fatal("parallel storage operations accepted")
	}
	for _, retired := range []string{"media", "mergeQueue", "mergeCleanup"} {
		if _, err := engine.workLease(retired, "start"); err == nil {
			t.Fatalf("retired task accepted: %s", retired)
		}
	}
	if count, err := engine.workLease("storage", "end"); err != nil || count != 0 {
		t.Fatalf("end: %d %v", count, err)
	}
}

func TestPathsOverlapAllowsSiblingsAndOtherVolumes(t *testing.T) {
	root := filepath.Join(t.TempDir(), "zhenguojian-downloads")
	cases := []struct {
		path    string
		overlap bool
	}{
		{root, true},
		{filepath.Join(root, "nested"), true},
		{filepath.Dir(root), true},
		{filepath.Join(filepath.Dir(root), "sibling"), false},
		{filepath.Join(filepath.Dir(root), "..zhenguojian-downloads"), false},
	}
	if runtime.GOOS == "windows" {
		volume := "D:"
		if strings.EqualFold(filepath.VolumeName(root), volume) {
			volume = "E:"
		}
		cases = append(cases, struct {
			path    string
			overlap bool
		}{volume + `\zhenguojian-downloads`, false})
	}
	for _, item := range cases {
		if got := nativePathsOverlap(root, item.path); got != item.overlap {
			t.Fatalf("%s: overlap=%v want %v", item.path, got, item.overlap)
		}
	}
}

func TestMigrationRejectsContainmentAndSymbolicLinks(t *testing.T) {
	engine, _ := storageFixture(t)
	if err := engine.moveDownloads(context.Background(), engine.downloads.root); err == nil {
		t.Fatal("nested destination accepted")
	}
	outside := t.TempDir()
	if err := os.Symlink(outside, filepath.Join(engine.downloads.root, "link")); err != nil {
		t.Skip(err)
	}
	if err := engine.moveDownloads(context.Background(), t.TempDir()); err == nil {
		t.Fatal("followed symlink")
	}
	if _, err := os.Stat(outside); err != nil {
		t.Fatal("removed linked directory")
	}
}
