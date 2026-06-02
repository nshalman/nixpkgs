#!/usr/bin/env bash
# Import a bootstrap-tools closure into /nix/store and register GC roots.
#
# Usage:
#   load-illumos-closure.sh <closure.nar.xz> <closure-roots.txt>
#
# Inputs are the two artifacts produced by
# pkgs/stdenv/illumos-recipe/make-bootstrap-tools.nix and declared in
# ./x86_64-illumos.nix. Both can be raw downloaded files OR /nix/store
# paths emitted by the fetchurl wrappers.
#
# Payload format (xz-compressed NAR; root layout after restore):
#   ./nix/store/<each-closure-path>/...
#   ./nix-path-registration
#
# Receiver requirements: nix-store on PATH, xz on PATH, write access to
# /nix/store and /nix/var/nix. NO stdenv / nixpkgs evaluation needed —
# this is the path that lets a fresh zone (just `nix` installed) populate
# its store without first compiling anything.
#
# Idempotent: paths already in /nix/store are skipped; nix-store --load-db
# tolerates re-registrations.

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "usage: $0 <closure.nar.xz> <closure-roots.txt>" >&2
    exit 1
fi

CLOSURE_NAR_XZ=$1
CLOSURE_ROOTS=$2

for f in "$CLOSURE_NAR_XZ" "$CLOSURE_ROOTS"; do
    if [ ! -f "$f" ]; then
        echo "error: $f is not a regular file" >&2
        exit 1
    fi
done

NIX_STORE=${NIX_STORE_DIR:-/nix/store}
NIX_STATE=${NIX_STATE_DIR:-/nix/var/nix}

for d in "$NIX_STORE" "$NIX_STATE"; do
    if [ ! -d "$d" ]; then
        echo "error: $d does not exist" >&2
        exit 1
    fi
done

for cmd in nix-store xz mktemp basename; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "error: $cmd not on PATH" >&2
        exit 1
    fi
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "==> restoring NAR payload to $WORK/payload"
xz -dc "$CLOSURE_NAR_XZ" | nix-store --restore "$WORK/payload"

if [ ! -d "$WORK/payload/nix/store" ]; then
    echo "error: payload missing nix/store/ — wrong artifact format?" >&2
    exit 2
fi
if [ ! -f "$WORK/payload/nix-path-registration" ]; then
    echo "error: payload missing nix-path-registration — wrong artifact format?" >&2
    exit 2
fi

echo "==> installing store paths to $NIX_STORE"
copied=0
skipped=0
for src in "$WORK/payload/nix/store"/*; do
    bn=$(basename "$src")
    dst="$NIX_STORE/$bn"
    if [ -e "$dst" ]; then
        skipped=$((skipped + 1))
    else
        mv "$src" "$dst"
        copied=$((copied + 1))
    fi
done
echo "    copied: $copied, skipped (already present): $skipped"

echo "==> registering paths in nix database"
nix-store --load-db < "$WORK/payload/nix-path-registration"

echo "==> registering GC roots under $NIX_STATE/gcroots/illumos-bootstrap"
GCROOTS="$NIX_STATE/gcroots/illumos-bootstrap"
mkdir -p "$GCROOTS"
roots=0
while IFS= read -r line; do
    # closure-roots.txt is whitespace-separated on a single line as
    # written by make-bootstrap-tools.nix (printf '%s\n' ${toString ...}).
    # Split on whitespace; tolerate either layout for forward-compat.
    for p in $line; do
        [ -z "$p" ] && continue
        bn=$(basename "$p")
        ln -sf "$p" "$GCROOTS/$bn"
        roots=$((roots + 1))
    done
done < "$CLOSURE_ROOTS"
echo "    $roots roots registered"

echo "==> done"
