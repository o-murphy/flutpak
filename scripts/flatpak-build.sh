#!/usr/bin/env bash

lint_flatpak_manifest() {
  local manifest_path="${1:?Usage: lint_flatpak_manifest <manifest.yml>}"
  flatpak-builder-lint --exceptions manifest "$(realpath "$manifest_path")"
}

build_flatpak() {
  local manifest="${1:?Usage: build_flatpak <manifest.yml>}"
  flathub-build "$(realpath "$manifest")"
}

lint_flatpak_repo() {
  local repo_path="${1:?Usage: lint_flatpak_repo <repo_path>}"
  flatpak-builder-lint --exceptions repo "$(realpath "$repo_path")"
}

export_flatpak_bundle() {
  local arch="${1:?Usage: export_flatpak_bundle <arch> <repo> <output> <app_id>}"
  local repo="${2:?Usage: export_flatpak_bundle <arch> <repo> <output> <app_id>}"
  local output="${3:?Usage: export_flatpak_bundle <arch> <repo> <output> <app_id>}"
  local app_id="${4:?Usage: export_flatpak_bundle <arch> <repo> <output> <app_id>}"
  flatpak build-bundle \
    --arch="$arch" \
    "$repo" \
    "$output" \
    "$app_id"
}
