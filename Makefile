# The one file, for each platform it runs on.
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null | sed 's/^v//' || echo dev)
LDFLAGS := -s -w -X main.version=$(VERSION)
PLATFORMS := linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64
# The core's packages, named so a stray directory in the tree never breaks a target.
PKGS := ./cmd/... ./internal/...
# The linters, pinned and run without adding them to go.mod.
LINT := go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.15.0
VULNCHECK := go run golang.org/x/vuln/cmd/govulncheck@v1.9.0

.PHONY: build run test lint vuln cover fmt dist plugin plugins plugin-digest plugins-check ui ui-dev astro astro-e2e clean

build:
	CGO_ENABLED=0 go build -trimpath -ldflags '$(LDFLAGS)' -o dist/librepublish ./cmd/librepublish

run:
	go run ./cmd/librepublish serve --data ./data

# vet, then the tests, race-checked and in random order.
test:
	go vet $(PKGS)
	go test -race -shuffle=on $(PKGS)

# golangci-lint, as .golangci.yml configures it.
lint:
	$(LINT) run $(PKGS)

# Known vulnerabilities in code the binary actually calls.
vuln:
	$(VULNCHECK) $(PKGS)

# The tests' total coverage, with the per-function detail in coverage.out.
cover:
	go test -race -covermode=atomic -coverprofile=coverage.out $(PKGS)
	go tool cover -func=coverage.out | tail -1

# gofumpt and goimports, rewriting files in place.
fmt:
	$(LINT) fmt $(PKGS)

# The admin (ui/, Svelte + Tailwind) into internal/admin/dist, which the
# binary embeds. Committed, so building the binary needs no Node.
ui:
	cd ui && npm ci && npm run check && npm run build

# The admin with hot reload on :5173, against `make run` on :8080.
ui-dev:
	cd ui && npm run dev

# The Astro integration (packages/astro): build, types, and its tests on
# contracts/ — the other half of the contract gate TestContract starts.
astro:
	cd packages/astro && npm ci && npm run build && npm run typecheck && npm test

# The example site against a freshly built core, end to end.
astro-e2e: build
	cd packages/astro && npm ci && npm run build && (cd example && npm ci) && LIBREPUBLISH_BIN=$(CURDIR)/dist/librepublish npm run e2e

# dist/librepublish-<os>-<arch>[.exe] and dist/checksums.txt: what a release
# attaches, and what install.sh downloads.
dist:
	@rm -rf dist && mkdir -p dist
	@for p in $(PLATFORMS); do \
	  os=$${p%/*}; arch=$${p#*/}; ext=; [ $$os = windows ] && ext=.exe; \
	  echo "librepublish-$$os-$$arch$$ext ($(VERSION))"; \
	  CGO_ENABLED=0 GOOS=$$os GOARCH=$$arch go build -trimpath -ldflags '$(LDFLAGS)' -o dist/librepublish-$$os-$$arch$$ext ./cmd/librepublish || exit 1; \
	done
	cd dist && sha256sum librepublish-* > checksums.txt

# The default plugins the binary ships (internal/cms/defaults), each built
# from plugins/<key>, with a digest of its source beside it so CI can tell
# a stale .wasm without depending on the Go patch release that built it.
DEFAULT_PLUGINS := forms
plugins:
	@for p in $(DEFAULT_PLUGINS); do \
	  echo "plugins/$$p -> internal/cms/defaults/$$p.wasm"; \
	  (cd plugins/$$p && GOOS=wasip1 GOARCH=wasm go build -trimpath -ldflags='-s -w' -buildmode=c-shared -o ../../internal/cms/defaults/$$p.wasm .) || exit 1; \
	  $(MAKE) -s plugin-digest P=$$p > internal/cms/defaults/$$p.src.sha256; \
	done

plugin-digest:
	@cd plugins/$(P) && find . -name '*.go' -o -name go.mod -o -name go.sum | LC_ALL=C sort | xargs sha256sum | sha256sum | cut -d' ' -f1

plugins-check:
	@for p in $(DEFAULT_PLUGINS); do \
	  test "$$($(MAKE) -s plugin-digest P=$$p)" = "$$(cat internal/cms/defaults/$$p.src.sha256)" || { echo "internal/cms/defaults/$$p.wasm is stale: run make plugins"; exit 1; }; \
	done

# The example plugin, as an uploadable .wasm.
plugin:
	cd plugins/visits && GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o ../../dist/visits.wasm .

clean:
	rm -rf dist coverage.out
