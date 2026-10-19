# Release builds (docs/release.md). CI calls these same targets, so a local
# release build gets exactly the version CI would. Nothing here names the app.

# The versionName is the pubspec's `version:`. The versionCode is the number of
# v* tags: one per release, so it can't be forgotten or reused. Never delete a
# released tag; if one is wrong, tag forward.
VERSION_NAME := $(shell awk '/^version:/ {print $$2; exit}' pubspec.yaml | cut -d+ -f1)
BUILD_NUMBER := $(shell git tag --list 'v[0-9]*' 2>/dev/null | wc -l | tr -d ' ')

.PHONY: help check-version build-aab changelog

help:
	@echo "make build-aab    signed release bundle, versionName $(VERSION_NAME), versionCode $(BUILD_NUMBER)"
	@echo "make changelog    release notes for this versionCode (ARGS='--dry-run' to only print)"

check-version:
	@test "$(BUILD_NUMBER)" -gt 0 2>/dev/null || { \
	  echo "error: no v* tags, so there's no versionCode. Tag the release first: git tag v$(VERSION_NAME)" >&2; exit 1; }

## build-aab: the bundle Play takes, signed with the upload key from android/key.properties
build-aab: check-version
	flutter build appbundle --release \
	  --build-name=$(VERSION_NAME) --build-number=$(BUILD_NUMBER) \
	  --dart-define=APP_VERSION=$(VERSION_NAME)

## changelog: write android/fastlane/metadata/android/en-US/changelogs/<versionCode>.txt
changelog:
	python3 -I tool/gen_changelog.py $(ARGS)
