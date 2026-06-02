#!/usr/bin/env bash
#
# Build and audit the bootstrap-tools v2 closure (bd nix-pb0.2).
#
# Produces, under ./result/on-server/ (symlinks into /nix/store):
#   closure.nar.xz       xz-compressed NAR of the stage-3 closure
#                        (payload layout: nix/store/<each>/... +
#                        nix-path-registration)
#   closure-roots.txt    explicit GC roots (bootstrap-tools-packages)
#
# This script does NOT upload anything anywhere. After a clean run it
# prints the absolute store paths + sha256s of both artifacts; the
# operator scp-s them to wherever they're being hosted. Automating
# pushes to a public web server from a build script is a foot-gun
# we deliberately don't ship.
#
# Precondition for fast & wedge-free operation: the stage-3 stdenv
# outputs that bootstrap-tools-packages references must already be in
# /nix/store on this host. A dry-run is performed first and the script
# warns loudly if any dep would actually be built — that's the path
# that hits the bash 5.3p3 autoconf wedge (bd nix-dl3) on illumos.
# A retry loop with halving -j mitigates the wedge if it triggers.
#
# Usage:
#   build-bootstrap-closure.sh [-C <nixpkgs-dir>] [-j <jobs>]
#                              [--max-retries <n>]
#
# Env defaults (override via flags):
#   NIXPKGS_DIR     /tmp/nixpkgs
#   NIX_JOBS        8
#   MAX_RETRIES     4
#
# Exit codes:
#   0 — closure built and audit clean
#   1 — usage / precondition failure
#   2 — audit found forbidden refs
#   3 — build failed after all retries

set -euo pipefail

NIXPKGS_DIR=${NIXPKGS_DIR:-/tmp/nixpkgs}
NIX_JOBS=${NIX_JOBS:-8}
MAX_RETRIES=${MAX_RETRIES:-4}

while [ $# -gt 0 ]; do
    case "$1" in
        -C)              NIXPKGS_DIR="$2";  shift 2 ;;
        -j)              NIX_JOBS="$2";     shift 2 ;;
        --max-retries)   MAX_RETRIES="$2";  shift 2 ;;
        -h|--help)       sed -n '2,/^set -euo/p' "$0" | sed '/^set -euo/d' ; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

if [ ! -d "$NIXPKGS_DIR" ]; then
    echo "error: NIXPKGS_DIR ($NIXPKGS_DIR) is not a directory" >&2
    exit 1
fi
cd "$NIXPKGS_DIR"

echo "==> nixpkgs at $(pwd)"
echo "    branch:  $(git rev-parse --abbrev-ref HEAD)"
echo "    head:    $(git log --oneline -1)"

EXPR=pkgs/stdenv/illumos-recipe/make-bootstrap-tools.nix
AUDIT_EXPR=pkgs/stdenv/illumos-recipe/audit.nix

echo "==> dry-run: what would build?"
DRY_OUT=$(nix-build --dry-run "$EXPR" -A build -A closure-nar -A closure-roots 2>&1 || true)
echo "$DRY_OUT" | sed 's/^/    /'

# nix-build --dry-run reports "these derivations will be built" before
# the list of to-build .drvs; if that line is absent, nothing needs
# rebuilding (best case — just a packaging pass).
if printf '%s\n' "$DRY_OUT" | grep -qE 'will be built'; then
    echo "==> warning: at least one stage-3 dep is not in the store." >&2
    echo "    A from-source build may trigger the bash 5.3p3 wedge" >&2
    echo "    (bd nix-dl3). Retry loop will halve -j on each restart." >&2
fi

# --- build with retry --------------------------------------------------------

build_attempt=1
jobs="$NIX_JOBS"
while : ; do
    echo "==> build attempt $build_attempt (-j$jobs)"
    if nix-build "$EXPR" -A build -j"$jobs" --keep-going; then
        break
    fi
    rc=$?
    if [ "$build_attempt" -ge "$MAX_RETRIES" ]; then
        echo "==> build failed after $MAX_RETRIES attempts (rc=$rc)" >&2
        exit 3
    fi
    echo "==> attempt $build_attempt failed (rc=$rc); cleaning /tmp/nix-build-*.drv-0" >&2
    rm -rf /tmp/nix-build-*.drv-0 || true
    build_attempt=$((build_attempt + 1))
    jobs=$(( jobs / 2 ))
    [ "$jobs" -lt 1 ] && jobs=1
done

NAR=$(readlink -f result/on-server/closure.nar.xz)
ROOTS=$(readlink -f result/on-server/closure-roots.txt)
echo "==> built:"
echo "    $NAR"
echo "    $ROOTS"

# --- audit (closure cleanliness) ---------------------------------------------
#
# audit.nix's static check covers both bd nix-pb0.2 acceptance items:
#   - closurePatterns rejects 'proto-strap' / 'illumos-strap-tools'
#     anywhere in the closure path list.
#   - substringPatterns deep-greps every file for '/opt/local'.
# Building audit.nix -A bootstrap-tools either succeeds (clean) or
# leaves nix-build's stderr with the offending matches.
echo "==> static audit"
if ! nix-build "$AUDIT_EXPR" -A bootstrap-tools -j"$jobs"; then
    echo "==> audit FAILED — see above for forbidden refs" >&2
    exit 2
fi
echo "==> audit clean"

# --- hashes + sizes ----------------------------------------------------------
echo "==> artifact metadata"
SHA_NAR=$(sha256sum "$NAR" | awk '{print $1}')
SHA_ROOTS=$(sha256sum "$ROOTS" | awk '{print $1}')
SIZE_NAR=$(stat -c '%s' "$NAR" 2>/dev/null || /usr/bin/stat -f '%z' "$NAR")
SIZE_ROOTS=$(stat -c '%s' "$ROOTS" 2>/dev/null || /usr/bin/stat -f '%z' "$ROOTS")
cat <<EOF
    closure.nar.xz
      path:   $NAR
      sha256: $SHA_NAR
      size:   $SIZE_NAR bytes
    closure-roots.txt
      path:   $ROOTS
      sha256: $SHA_ROOTS
      size:   $SIZE_ROOTS bytes
EOF

# Both result/on-server/* entries are symlinks into /nix/store; scp -L
# (follow symlinks) reads the actual file contents.
cat <<EOF

==> to copy to another host:
    scp -L "$NAR" "$ROOTS" <dest>:<path>/

==> or pull from your workstation:
    scp -L <user>@<this-host>:$NAR <local>/
    scp -L <user>@<this-host>:$ROOTS <local>/
EOF

echo "==> done"
