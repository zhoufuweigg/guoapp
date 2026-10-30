package core

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
)

var nativeUpdateServer = ""

const nativeReleasePrefix = "https://github.com/Xanerix/guoapp/releases/"

var nativeAppVersionPattern = regexp.MustCompile(`^\d+\.\d+\.\d+\+(\d+)$`)
var nativeInstallIDPattern = regexp.MustCompile(`^[0-9a-f]{32}$`)

type nativeUpdate struct {
	Available bool   `json:"available"`
	Version   string `json:"version,omitempty"`
	URL       string `json:"url,omitempty"`
}

func nativeAppBuildNumber(version string) (int, bool) {
	match := nativeAppVersionPattern.FindStringSubmatch(version)
	if match == nil {
		return 0, false
	}
	number, err := strconv.Atoi(match[1])
	return number, err == nil
}

func (engine *nativeEngine) installID() (string, error) {
	path := filepath.Join(engine.directory, "install-id")
	if data, err := os.ReadFile(path); err == nil && nativeInstallIDPattern.Match(data) {
		return string(data), nil
	}
	buffer := make([]byte, 16)
	if _, err := rand.Read(buffer); err != nil {
		return "", err
	}
	id := hex.EncodeToString(buffer)
	return id, os.WriteFile(path, []byte(id), 0600)
}

func (engine *nativeEngine) reportUsage(ctx context.Context, version string) error {
	if _, valid := nativeAppBuildNumber(version); !valid {
		return errors.New("应用版本号无效")
	}
	if nativeUpdateServer == "" {
		return nil
	}
	id, err := engine.installID()
	if err != nil {
		return err
	}
	appBuild := "hongguojian"
	if buildAllSources == "true" {
		appBuild = "zhenguojian"
	}
	payload, err := json.Marshal(map[string]string{"id": id, "version": version, "platform": runtime.GOOS, "build": appBuild})
	if err != nil {
		return err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, nativeUpdateServer+"/v1/ping", bytes.NewReader(payload))
	if err != nil {
		return err
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := engine.downloader.client.Do(request)
	if err != nil {
		return err
	}
	response.Body.Close()
	if response.StatusCode/100 != 2 {
		return fmt.Errorf("使用统计失败：HTTP %d", response.StatusCode)
	}
	return nil
}

func (engine *nativeEngine) checkUpdate(ctx context.Context, version string) (nativeUpdate, error) {
	current, valid := nativeAppBuildNumber(version)
	if !valid {
		return nativeUpdate{}, errors.New("应用版本号无效")
	}
	if nativeUpdateServer == "" {
		return nativeUpdate{}, nil
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, nativeUpdateServer+"/v1/latest", nil)
	if err != nil {
		return nativeUpdate{}, err
	}
	response, err := engine.downloader.client.Do(request)
	if err != nil {
		return nativeUpdate{}, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nativeUpdate{}, fmt.Errorf("检查更新失败：HTTP %d", response.StatusCode)
	}
	var latest struct {
		Version string `json:"version"`
		URL     string `json:"url"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 4096)).Decode(&latest); err != nil {
		return nativeUpdate{}, err
	}
	number, valid := nativeAppBuildNumber(latest.Version)
	if !valid || number <= current || !strings.HasPrefix(latest.URL, nativeReleasePrefix) {
		return nativeUpdate{}, nil
	}
	return nativeUpdate{Available: true, Version: latest.Version, URL: latest.URL}, nil
}
