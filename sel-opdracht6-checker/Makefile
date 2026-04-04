APP        := sel-opdracht6-checker
CMD        := ./cmd/checker
VERSION    := $(shell cat version.txt)
LDFLAGS    := -s -w -X main.Version=$(VERSION)
GOFLAGS    := -ldflags="$(LDFLAGS)"
RELEASEDIR := releases

# Cross-compile targets
PLATFORMS := linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64 windows/arm64

.PHONY: help all build run clean release version tag bump-patch bump-minor bump-major

help:
	@echo "SELab Opdracht 6 Checker v$(VERSION)"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  all          Cross-compile all platforms into releases/"
	@echo "  build        Build the binary for the current platform"
	@echo "  run          Build and run (needs DECRYPT_PASS)"
	@echo "  clean        Remove all built binaries and releases/"
	@echo "  release      Alias for all"
	@echo "  version      Print the current version"
	@echo "  tag          Create a git tag for the current version"
	@echo "  bump-patch   Bump patch version (x.y.Z)"
	@echo "  bump-minor   Bump minor version (x.Y.0)"
	@echo "  bump-major   Bump major version (X.0.0)"
	@echo ""

version:
	@echo $(VERSION)

build:
	CGO_ENABLED=0 go build $(GOFLAGS) -o $(APP) $(CMD)

run: build
	DECRYPT_PASS="$${DECRYPT_PASS}" ./$(APP)

clean:
	rm -f $(APP)
	rm -rf $(RELEASEDIR)

all: clean
	@mkdir -p $(RELEASEDIR)
	@for platform in $(PLATFORMS); do \
		os=$${platform%/*}; \
		arch=$${platform#*/}; \
		ext=""; \
		[ "$$os" = "windows" ] && ext=".exe"; \
		out="$(RELEASEDIR)/$(APP)-$$os-$$arch$$ext"; \
		echo "  -> $$out"; \
		CGO_ENABLED=0 GOOS=$$os GOARCH=$$arch go build $(GOFLAGS) -o $$out $(CMD) || exit 1; \
	done
	@echo "  All binaries built ($(VERSION))"
	@ls -lh $(RELEASEDIR)/

release: all

# -- Version management --

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
