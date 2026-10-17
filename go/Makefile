# The one file, for each platform it runs on.
VERSION := $(shell grep -o '"[0-9][^"]*"' internal/cms/server.go | head -1 | tr -d '"')
LDFLAGS := -s -w
PLATFORMS := linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64

.PHONY: build test dist plugin clean

build:
	CGO_ENABLED=0 go build -trimpath -ldflags '$(LDFLAGS)' -o dist/librepublish ./cmd/librepublish

test:
	go vet ./...
	go test ./...

dist:
	@for p in $(PLATFORMS); do \
	  os=$${p%/*}; arch=$${p#*/}; ext=; [ $$os = windows ] && ext=.exe; \
	  echo "librepublish-$(VERSION)-$$os-$$arch$$ext"; \
	  CGO_ENABLED=0 GOOS=$$os GOARCH=$$arch go build -trimpath -ldflags '$(LDFLAGS)' -o dist/librepublish-$(VERSION)-$$os-$$arch$$ext ./cmd/librepublish || exit 1; \
	done

# The example plugin, as an uploadable .wasm.
plugin:
	cd plugins/visits && GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o ../../dist/visits.wasm .

clean:
	rm -rf dist
