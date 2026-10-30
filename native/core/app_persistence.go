package core

import (
	"errors"
	"strings"
)

const nativeCatalogMaxBytes = 32 << 20

const nativeCatalogMaxItems = 5000

var errNativeCatalogLimit = errors.New("剧库超过本地保存上限（32 MiB），新内容尚未保存，已暂停继续加载")

type nativePersistenceError struct {
	label string
	cause error
}

func (err *nativePersistenceError) Error() string {
	if errors.Is(err.cause, errNativeCatalogLimit) {
		return err.cause.Error()
	}
	return err.label + "尚未保存，最新结果仅在本次运行中保留；请检查剩余空间和存储权限后重试保存"
}

func (err *nativePersistenceError) Unwrap() error { return err.cause }

func nativeSaveError(label string, err error) error {
	if err == nil {
		return nil
	}
	return &nativePersistenceError{label: label, cause: err}
}

func joinNativeWarnings(warnings ...string) string {
	seen := map[string]bool{}
	var values []string
	for _, warning := range warnings {
		if warning != "" && !seen[warning] {
			seen[warning] = true
			values = append(values, warning)
		}
	}
	return strings.Join(values, "；")
}

func (engine *nativeEngine) retryCatalogSave() (bool, error) {
	engine.mu.Lock()
	defer engine.mu.Unlock()
	if engine.catalogSaveError == nil {
		return false, nil
	}
	return true, engine.writeCatalogDiskLocked()
}
