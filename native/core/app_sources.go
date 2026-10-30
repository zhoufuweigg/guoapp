package core

import "context"

func (engine *nativeEngine) lockSourceCatalog(ctx context.Context, source string) (func(), error) {
	engine.sourceCatalogMu.Lock()
	if engine.sourceCatalogs == nil {
		engine.sourceCatalogs = map[string]chan struct{}{}
	}
	gate := engine.sourceCatalogs[source]
	if gate == nil {
		gate = make(chan struct{}, 1)
		engine.sourceCatalogs[source] = gate
	}
	engine.sourceCatalogMu.Unlock()
	select {
	case gate <- struct{}{}:
		return func() { <-gate }, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}
