#!/usr/bin/bash
#
# Required environment (set by default.nix derivation attrs):
#   $out             install prefix
#   $origOut         gcc-illumos.out path to scrub
#   $protoStrapPath  proto-strap store path (used to extract its hash)
#   $python3Path     nix-built python3 (binary at $python3Path/bin/python3)
#   $gnugrepPath     nix-built gnugrep (binary at $gnugrepPath/bin/grep)
#
# The scrub neutralizes three classes of byte references in $out so the
# resulting store path has a clean closure with no proto-strap and no
# /opt/local:
#   1. proto-strap store path hash -- replaced with an invalid nix32
#      hash. Drops proto-strap from the closure entirely.
#   2. original gcc-illumos.out store path hash (i.e., $origOut's hash) --
#      same replacement strategy. gcc's compiled-in --prefix paths become
#      invalid, but gcc's driver-relative path fallback kicks in (verified
#      via `gcc -print-search-dirs`); functional behavior is preserved.
#   3. /opt/local string occurrences -- replaced with /dev/null/, same
#      length. The only known occurrence is /opt/local/bin/sed in
#      libexec/.../install-tools/fixincl, which is invoked only during
#      a gcc-bootstrap (not during normal compilation), so the resulting
#      ENOENT is harmless for downstream tarball use.

set -euo pipefail
set -o xtrace

python3="$python3Path/bin/python3"
grep_="$gnugrepPath/bin/grep"
[ -x "$python3" ] || { echo "missing python3 at $python3" >&2; exit 1; }
[ -x "$grep_" ]   || { echo "missing grep at $grep_" >&2; exit 1; }

# Build the replacement table.
proto_hash="$(basename "$protoStrapPath" | cut -c1-32)"
orig_hash="$(basename "$origOut" | cut -c1-32)"

# Invalid-nix32-alphabet variants: replace leading char with 'e'.
# Nix store-hash alphabet excludes 'e/o/t/u', so prefixing with 'e'
# defeats the closure scanner.
proto_hash_scrubbed="e${proto_hash:1}"
orig_hash_scrubbed="e${orig_hash:1}"

# Same-length replacements. /opt/local is 10 chars, /dev/null/ is 10 chars.
declare -a NEEDLE_OLD=(
    "${proto_hash}-proto-strap"
    "${orig_hash}-gcc-illumos"
    "/opt/local"
)
declare -a NEEDLE_NEW=(
    "${proto_hash_scrubbed}-proto-strap"
    "${orig_hash_scrubbed}-gcc-illumos"
    "/dev/null/"
)

# Sanity: each replacement must be the same length as the original.
for i in "${!NEEDLE_OLD[@]}"; do
    [ "${#NEEDLE_OLD[$i]}" = "${#NEEDLE_NEW[$i]}" ] \
        || { echo "length mismatch for needle $i" >&2; exit 1; }
    echo "needle $i: ${NEEDLE_OLD[$i]} -> ${NEEDLE_NEW[$i]}"
done

# Copy origOut to $out (writable).
mkdir -p "$out"
cp -R "$origOut"/. "$out"/
chmod -R u+w "$out"

# Walk every file once; for each, apply every needle that has a match.
find "$out" -type f -print0 | while IFS= read -r -d '' f; do
    for i in "${!NEEDLE_OLD[@]}"; do
        if "$grep_" -alF "${NEEDLE_OLD[$i]}" "$f" >/dev/null 2>&1; then
            "$python3" - "$f" "${NEEDLE_OLD[$i]}" "${NEEDLE_NEW[$i]}" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2].encode(), sys.argv[3].encode()
assert len(old) == len(new), "length mismatch (should not happen)"
with open(path, "rb") as fp:
    data = fp.read()
data2 = data.replace(old, new)
if data2 != data:
    with open(path, "wb") as fp:
        fp.write(data2)
PY
            echo "scrubbed needle $i in: $f"
        fi
    done
done

# Sanity-check: no needle should remain anywhere in $out.
fail=0
for i in "${!NEEDLE_OLD[@]}"; do
    remaining="$("$grep_" -rlF "${NEEDLE_OLD[$i]}" "$out" 2>/dev/null || true)"
    if [ -n "$remaining" ]; then
        echo "scrub failed; needle $i (${NEEDLE_OLD[$i]}) refs remain in:" >&2
        echo "$remaining" >&2
        fail=1
    fi
done
[ "$fail" = 0 ] || exit 1

echo "scrub complete; all needles eliminated from $out"
