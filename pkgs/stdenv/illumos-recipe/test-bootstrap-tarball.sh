#!/usr/bin/env bash
#
# Smoke-test that a bootstrap-tools tarball is self-sufficient on an
# illumos zone without /opt/local. Intended workflow:
#
#   1) Build the tarball on the builder zone:
#        nix-build pkgs/stdenv/illumos-recipe/make-bootstrap-tools.nix \
#                  -A bootstrap-tools --no-out-link
#      (Use -A build to also get the unpack.nar.xz alongside it.)
#
#   2) Copy bootstrap-tools.tar.xz to the test zone.
#
#   3) Manually move /opt/local aside (Nahum's preference: do this by
#      hand, not from this script — keeps the zone's state predictable):
#        mv /opt/local /opt/local.aside
#
#   4) Run this script with the tarball path:
#        ./test-bootstrap-tarball.sh /path/to/bootstrap-tools.tar.xz
#
#   5) Restore /opt/local after testing:
#        mv /opt/local.aside /opt/local
#
# The script unpacks the tarball into a temp dir, narrows PATH to only
# the extracted tree + /usr/bin + /usr/sbin (no /opt/local, no
# /nix/var/nix/profiles/default), and runs a representative set of
# build operations. Failure modes that matter:
#   - missing tool      → tarball is incomplete
#   - "Bad ELF interpreter" / "not found" → binary's RUNPATH points at
#     a /nix/store path that was supposed to be in the tarball but
#     isn't (or the extracted tree's layout isn't what binaries expect)
#   - /opt/local in error output → not clean
#
# This is a *single-tree* test of the tarball's flat bin/lib/etc.
# layout. It does not verify the full nix-store consumption path
# (where binaries' /nix/store RUNPATHs are expected to resolve against
# a populated /nix/store) — that test is a separate concern.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <bootstrap-tools.tar.xz>" >&2
    exit 64
fi

tarball="$1"
if [ ! -f "$tarball" ]; then
    echo "error: $tarball not found" >&2
    exit 1
fi

# Refuse to run if /opt/local exists with expected pkgsrc content. The
# whole point of the test is /opt/local being absent. Bail loudly
# rather than producing false confidence.
if [ -d /opt/local/bin ] && ls /opt/local/bin/* >/dev/null 2>&1; then
    cat >&2 <<'EOM'
error: /opt/local/bin exists and is populated. This test only proves
the tarball is /opt/local-free if /opt/local is absent. Move it aside
manually first:
    mv /opt/local /opt/local.aside
and re-run this script. Restore afterward.
EOM
    exit 2
fi

work=$(mktemp -d -t boottest.XXXXXX)
trap 'rm -rf "$work"' EXIT
echo "==> Test root: $work"

# Use the system tar/xz to unpack — they're outside the tarball, in
# /usr/bin, and don't depend on /opt/local.
echo "==> Extracting $tarball"
mkdir -p "$work/root"
/usr/bin/tar -xJf "$tarball" -C "$work/root"

# Inventory check: every binary listed below must exist.
must_have=(
    bin/bash
    bin/gmake
    bin/gawk
    bin/gnused bin/sed
    bin/gnugrep bin/grep
    bin/gcc bin/g++
    bin/ld bin/as bin/ar bin/nm bin/strip
    bin/tar bin/xz bin/gzip
)
echo "==> Inventory check"
missing=0
for f in "${must_have[@]}"; do
    # Some entries are alternatives separated by spaces above — accept any.
    found=0
    for cand in $f; do
        if [ -e "$work/root/$cand" ]; then
            found=1
            break
        fi
    done
    if [ $found -eq 0 ]; then
        echo "  MISSING: any of: $f" >&2
        missing=1
    fi
done
if [ $missing -ne 0 ]; then
    echo "==> tarball is missing required tools" >&2
    exit 3
fi

# Narrowed PATH: tarball + system /usr/bin only. Explicitly NOT
# including /opt/local (which is absent anyway) or
# /nix/var/nix/profiles/default (which carries the zone's existing
# nix-store-resolved binaries — we want to test the tarball, not
# pre-existing state).
export PATH="$work/root/bin:/usr/bin:/usr/sbin"
unset LD_LIBRARY_PATH LD_LIBRARY_PATH_64 LD_LIBRARY_PATH_32

echo "==> PATH is: $PATH"
echo "==> Version checks"
"$work/root/bin/bash" --version | head -1
"$work/root/bin/gmake" --version | head -1
"$work/root/bin/gcc" --version | head -1
"$work/root/bin/ld" --version 2>&1 | head -1 || true

# Hello-world compile + link via the tarball's gcc.
src="$work/hello.c"
cat >"$src" <<'EOF'
#include <stdio.h>
int main(void) { printf("hello from tarball\n"); return 0; }
EOF
echo "==> compile + link hello.c via $work/root/bin/gcc"
"$work/root/bin/gcc" -O2 -o "$work/hello" "$src"

echo "==> exec result"
"$work/hello"

echo "==> ldd of result"
ldd "$work/hello" | sed 's/^/    /'

# Scan the executed binary for /opt/local literal refs. If any survive
# at runtime, the binary baked them in via configure-time discovery.
if strings "$work/hello" | grep -F /opt/local; then
    echo "FAIL: hello binary contains /opt/local string refs" >&2
    exit 4
fi
echo "==> hello binary has zero /opt/local string refs"

echo "==> ALL CHECKS PASSED"
