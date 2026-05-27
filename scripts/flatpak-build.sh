#!/usr/bin/env bash

# Use dbus-run-session only when there is no existing dbus session (CI).
# Locally, a desktop session is running; spawning a nested one conflicts
# with the FUSE document portal already mounted at /run/user/$UID/doc.
_dbus_run() {
  if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    dbus-run-session "$@"
  else
    "$@"
  fi
}

install_flatpak_builder() {
  if ! command -v flatpak &>/dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y flatpak
  fi
  flatpak remote-add --user --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
  _dbus_run flatpak install --user -y --noninteractive flathub \
    org.flatpak.Builder
}

lint_flatpak_manifest() {
  local manifest_path="${1:?Usage: lint_flatpak_manifest <manifest.yml>}"
  _dbus_run flatpak run \
    --filesystem=host \
    --command=flatpak-builder-lint \
    org.flatpak.Builder \
    --exceptions \
    manifest "$(realpath "$manifest_path")"
}

build_flatpak() {
  local manifest="${1:?Usage: build_flatpak <manifest.yml>}"
  _dbus_run flatpak run --command=flathub-build org.flatpak.Builder \
    "$(realpath "$manifest")"
}

lint_flatpak_repo() {
  local repo_path="${1:?Usage: lint_flatpak_repo <repo_path>}"
  _dbus_run flatpak run \
    --filesystem=host \
    --command=flatpak-builder-lint \
    org.flatpak.Builder \
    --exceptions \
    repo "$(realpath "$repo_path")"
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
