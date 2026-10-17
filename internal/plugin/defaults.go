package plugin

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"io/fs"
	"path"
	"slices"
)

// EnsureDefaults installs the plugins the binary ships, or upgrades them:
// on first run they're granted what they ask for and switched on; a new
// binary upgrades them in place. Someone who removes one has removed it:
// it isn't put back. settings/default_plugins keeps track: {key:
// {"sha256", "removed"}}.
func (h *Host) EnsureDefaults(ctx context.Context) {
	entries, _ := fs.ReadDir(h.defaults, ".")
	state, err := h.env.Setting(ctx, "default_plugins")
	if err != nil {
		// Unreadable state isn't "nothing installed": leave things be.
		h.log.Warn("default plugins", "err", err)
		return
	}
	changed := false
	for _, e := range entries {
		wasm, err := fs.ReadFile(h.defaults, e.Name())
		if err != nil {
			continue
		}
		sum := sha256.Sum256(wasm)
		digest := hex.EncodeToString(sum[:])
		key := e.Name()[:len(e.Name())-len(path.Ext(e.Name()))]
		prev, _ := state[key].(map[string]any)
		if prev["removed"] == true || (prev["sha256"] == digest && h.Get(key) != nil) {
			continue
		}
		before := h.Get(key)
		p, err := h.Install(ctx, nil, wasm)
		if err != nil {
			h.log.Warn("default plugin", "plugin", key, "err", err)
			continue
		}
		// First party: what it asks for is granted. A new install is
		// switched on; an upgrade stays as on or off as it was.
		on := before == nil || before.Enabled
		if _, err := h.Configure(ctx, nil, p.Key, &p.Manifest.Permissions, &on); err != nil {
			h.log.Warn("default plugin", "plugin", key, "err", err)
		}
		state[p.Key] = map[string]any{"sha256": digest, "version": p.Version}
		changed = true
	}
	if changed {
		if err := h.env.ReplaceSetting(ctx, "default_plugins", state); err != nil {
			h.log.Warn("default plugins", "err", err)
		}
	}
}

// isDefault says whether a plugin came with the binary.
func (h *Host) isDefault(key string) bool {
	entries, _ := fs.ReadDir(h.defaults, ".")
	return slices.ContainsFunc(entries, func(e fs.DirEntry) bool { return e.Name() == key+".wasm" })
}

// forgetDefault records that a default plugin was removed on purpose.
func (h *Host) forgetDefault(ctx context.Context, key string) error {
	if !h.isDefault(key) {
		return nil
	}
	state, err := h.env.Setting(ctx, "default_plugins")
	if err != nil {
		return err
	}
	state[key] = map[string]any{"removed": true}
	return h.env.ReplaceSetting(ctx, "default_plugins", state)
}
