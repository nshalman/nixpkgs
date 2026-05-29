#!/usr/bin/bash
#
# Thin builder.sh that translates derivation env vars into command-line
# args for make-joyent-image.sh, then lands its output in $out.
#
# Required env (set by make-joyent-image.nix):
#   $out                nix output path (a directory)
#   $parentDataset      parent ZFS dataset
#   $zoneImage          store path to a nix-zone-image.tar.xz
#   $zoneRoot           store path to an illumos-zone-root.tar.xz
#   $imageName $imageVersion $imageDescription
#   $driver             path to make-joyent-image.sh

set -euo pipefail
set -o xtrace

mkdir -p "$out"

exec "$driver" \
    --parent-dataset "$parentDataset" \
    --zone-image     "$zoneImage" \
    --zone-root      "$zoneRoot" \
    --name           "$imageName" \
    --version        "$imageVersion" \
    --description    "$imageDescription" \
    --out-dir        "$out"
