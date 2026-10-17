package cms

import (
	"embed"
	"io/fs"
)

// The default plugins ship inside the binary, built from plugins/<key> by
// `make plugins`; the plugin host installs them (plugin.Host.EnsureDefaults).
//
//go:embed defaults/*.wasm
var defaultPluginFiles embed.FS

// defaultPlugins is the shipped .wasm files, at the root.
func defaultPlugins() fs.FS {
	sub, err := fs.Sub(defaultPluginFiles, "defaults")
	if err != nil {
		panic(err) // "defaults" is a valid path
	}
	return sub
}
