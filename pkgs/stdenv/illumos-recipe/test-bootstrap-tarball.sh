#!/usr/bin/env bash
#
# Verify that a bootstrap-tools.tar.xz contains zero /opt/local string
# refs (and the other forbidden patterns the static audit also checks).
#
# This is the runtime companion to `audit.nix -A bootstrap-tools`:
#   - The static audit grep-scans the *nix-store closure* of the
#     bootstrap-tools packages list at eval/build time.
#   - This script grep-scans the *extracted tarball contents* — useful
#     when you've received a tarball as a file (no nix store access)
#     and want a second-opinion check before publishing or shipping.
#
# What this script does NOT do: run binaries from the extracted tree.
# The tarball's contents have absolute /nix/store/<hash>/lib RUNPATHs
# baked in by the build — running them from an arbitrary extraction
# point would fail at link time, but that failure mode is unrelated to
# /opt/local cleanliness. End-to-end execution testing needs the
# bootstrap-files unpacker (parallel to freebsd/unpack-bootstrap-files.sh),
# which patchelf-rewrites RUNPATHs to the unpacked location. That's
# out of scope here.
#
# Usage:
#   ./test-bootstrap-tarball.sh <bootstrap-tools.tar.xz>
#
# Exit codes:
#   0 — clean
#   1 — usage / file-not-found
#   2 — forbidden refs found

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <bootstrap-tools.tar.xz>" >&2
    exit 1
fi

tarball="$1"
if [ ! -f "$tarball" ]; then
    echo "error: $tarball not found" >&2
    exit 1
fi

# Forbidden patterns — keep in sync with audit.nix's `forbidden` list.
forbidden=(
    "/opt/local"
    "illumos-strap-tools"
    "proto-strap"
)

work=$(mktemp -d -t boottest.XXXXXX)
trap 'rm -rf "$work"' EXIT
echo "==> extracting $tarball into $work"
/usr/bin/tar -xJf "$tarball" -C "$work"

# Use system grep here. We're scanning files that may be ELF binaries;
# illumos /usr/bin/grep treats binary input as a single "no match" line
# without `-a`, so prefer GNU grep if available, falling back to
# /usr/bin/grep with explicit binary handling.
if [ -x /opt/local/bin/ggrep ]; then
    GREP=/opt/local/bin/ggrep
elif [ -x /opt/local/bin/grep ]; then
    GREP=/opt/local/bin/grep
else
    GREP=/usr/bin/grep
fi
echo "==> using $GREP"

bad=0
for pat in "${forbidden[@]}"; do
    if hits=$("$GREP" -ralF "$pat" "$work" 2>/dev/null) && [ -n "$hits" ]; then
        echo "FORBIDDEN: tarball contains '$pat' in:" >&2
        printf '    %s\n' $hits >&2
        bad=1
    fi
done

if [ "$bad" = 1 ]; then
    echo "==> tarball is NOT clean" >&2
    exit 2
fi

echo "==> tarball clean (no forbidden refs across $(find "$work" -type f | wc -l) files)"
