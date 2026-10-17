package cms

import (
	"context"
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"io/fs"
	"path"
	"slices"
)

// The default plugins ship inside the binary (built from plugins/<key> by
// `make plugins`) and install themselves: on first run they're granted what
// they ask for and switched on; a new binary upgrades them in place. Someone
// who removes one has removed it: it isn't put back.
//
//go:embed defaults/*.wasm
var defaultPluginFiles embed.FS

// defaultPlugins is settings/default_plugins: {key: {"sha256", "removed"}}.
func (h *PluginHost) EnsureDefaults(ctx context.Context) {
	entries, _ := defaultPluginFiles.ReadDir("defaults")
	state := h.app.Setting(ctx, "default_plugins")
	changed := false
	for _, e := range entries {
		wasm, err := defaultPluginFiles.ReadFile(path.Join("defaults", e.Name()))
		if err != nil {
			continue
		}
		sum := sha256.Sum256(wasm)
		digest := hex.EncodeToString(sum[:])
		key := e.Name()[:len(e.Name())-len(path.Ext(e.Name()))]
		prev, _ := state[key].(map[string]any)
		if prev["removed"] == true || (prev["sha256"] == digest && h.get(key) != nil) {
			continue
		}
		before := h.get(key)
		p, err := h.Install(ctx, nil, wasm)
		if err != nil {
			h.app.Logger.Warn("default plugin", "plugin", key, "err", err)
			continue
		}
		// First party: what it asks for is granted. A new install is
		// switched on; an upgrade stays as on or off as it was.
		on := before == nil || before.Enabled
		if _, err := h.Configure(ctx, nil, p.Key, &p.parsed.Permissions, &on); err != nil {
			h.app.Logger.Warn("default plugin", "plugin", key, "err", err)
		}
		state[p.Key] = map[string]any{"sha256": digest, "version": p.Version}
		changed = true
	}
	if changed {
		h.app.PutSetting(ctx, nil, "default_plugins", state, true)
	}
}

// isDefault says whether a plugin came with the binary.
func isDefault(key string) bool {
	entries, _ := defaultPluginFiles.ReadDir("defaults")
	return slices.ContainsFunc(entries, func(e fs.DirEntry) bool { return e.Name() == key+".wasm" })
}

// forgetDefault records that a default plugin was removed on purpose.
func (h *PluginHost) forgetDefault(ctx context.Context, key string) {
	if !isDefault(key) {
		return
	}
	state := h.app.Setting(ctx, "default_plugins")
	state[key] = map[string]any{"removed": true}
	h.app.PutSetting(ctx, nil, "default_plugins", state, true)
}
