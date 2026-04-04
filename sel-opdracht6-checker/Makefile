APP      := sel-opdracht6-checker
CMD      := ./cmd/checker
VERSION  := $(shell cat version.txt)
LDFLAGS  := -s -w -X main.Version=$(VERSION)
GOFLAGS  := -ldflags="$(LDFLAGS)"

# Cross-compile targets
PLATFORMS := linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64 windows/arm64

.PHONY: all build run clean release version tag bump-patch bump-minor bump-major

all: build

version:
	@echo $(VERSION)

build:
	CGO_ENABLED=0 go build $(GOFLAGS) -o $(APP) $(CMD)

run: build
	DECRYPT_PASS="$${DECRYPT_PASS}" ./$(APP)

clean:
	rm -f $(APP) $(APP)-*

release: clean
	@for platform in $(PLATFORMS); do \
		os=$${platform%/*}; \
		arch=$${platform#*/}; \
		ext=""; \
		[ "$$os" = "windows" ] && ext=".exe"; \
		out="$(APP)-$$os-$$arch$$ext"; \
		echo "  -> $$out"; \
		CGO_ENABLED=0 GOOS=$$os GOARCH=$$arch go build $(GOFLAGS) -o $$out $(CMD) || exit 1; \
	done
	@echo "  All binaries built ($(VERSION))"
	@ls -lh $(APP)-*

# -- Version management --------------------------------------------------

tag:
	git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	@echo "  Tagged v$(VERSION)"
	@echo "  Run 'git push origin v$(VERSION)' to trigger a release build"

bump-patch:
	@echo $(VERSION) | awk -F. '{printf "%d.%d.%d\n", $$1, $$2, $$3+1}' > version.txt
	@echo "  $(VERSION) -> $$(cat version.txt)"

bump-minor:
	@echo $(VERSION) | awk -F. '{printf "%d.%d.0\n", $$1, $$2+1}' > version.txt
	@echo "  $(VERSION) -> $$(cat version.txt)"

bump-major:
	@echo $(VERSION) | awk -F. '{printf "%d.0.0\n", $$1+1}' > version.txt
	@echo "  $(VERSION) -> $$(cat version.txt)"
