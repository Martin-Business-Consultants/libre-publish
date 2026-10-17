# The one file, for each platform it runs on.
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null | sed 's/^v//' || echo dev)
LDFLAGS := -s -w -X github.com/Martin-Business-Consultants/libre-publish/internal/cms.Version=$(VERSION)
PLATFORMS := linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64

.PHONY: build run test dist plugin clean

build:
	CGO_ENABLED=0 go build -trimpath -ldflags '$(LDFLAGS)' -o dist/librepublish ./cmd/librepublish

run:
	go run ./cmd/librepublish serve --data ./data

test:
	go vet ./...
	go test ./...

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

# The example plugin, as an uploadable .wasm.
plugin:
	cd plugins/visits && GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o ../../dist/visits.wasm .

clean:
	rm -rf dist
