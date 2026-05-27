#!/usr/bin/bash
#
# Builder for proto-strap: just unpack the SmartOS proto.strap tarball
# into $out. The tarball is laid out exactly as the SmartOS build cache
# stores it (usr/gcc/<MAJOR>/..., usr/gnu/bin/..., etc.); we preserve
# that layout so gcc-illumos can reference well-known paths like
# ${out}/usr/gcc/10/bin/gcc and ${out}/usr/gnu/bin/gas.

set -euo pipefail
set -o xtrace

export PATH="$unpackPath"

mkdir -p "$out"
tar xzf "$tarball" -C "$out"
