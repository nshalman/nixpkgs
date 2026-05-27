#!/usr/bin/bash
#
# Builder for gcc-illumos: stages the SmartOS-recipe GCC build under
# Nix without depending on the nixpkgs stdenv chain.
#
# Required environment (set by default.nix derivation attrs):
#   $out         install prefix
#   $src         gcc source tarball (github.com/illumos/gcc)
#   $mpfrSrc     mpfr tarball
#   $gmpSrc      gmp tarball
#   $mpcSrc      mpc tarball
#   $patchFile   adapted *-ld-flags.patch for this GCC version
#   $hostPath    colon-separated PATH for the host toolchain
#                (host compiler's gcc/g++/gas dirs first, then extras
#                 for make/gawk/patch/flex/bison/...)
#   $asPath      absolute path to GNU assembler (gas)
#   $version     e.g. "14.2.0-il-1" or "10.4.0-il-2"
#   $mpfrVer     e.g. "mpfr-4.2.1"
#   $gmpVer      e.g. "gmp-6.3.0"
#   $mpcVer      e.g. "mpc-1.3.1"
#
# Optional environment:
#   $coresCap    cap on `make -j`. 0 (default) = no cap, use
#                NIX_BUILD_CORES verbatim (with the gnu-make -j0 quirk
#                translated to plain -j).
#
# Output: $out/bin/gcc, $out/lib/amd64/libgcc_s.so.1, etc.

set -euo pipefail
set -o xtrace

export PATH="$hostPath"

# Sanity-check host toolchain.
for tool in bash gcc g++ make sed awk tar patch; do
    type -p "$tool" >/dev/null || { echo "missing host tool: $tool" >&2; exit 1; }
done
[ -x /usr/bin/ld ] || { echo "missing /usr/bin/ld" >&2; exit 1; }
[ -x "$asPath" ] || { echo "missing assembler at $asPath" >&2; exit 1; }

# Workspace.
workdir="$(pwd)"
srcdir="$workdir/gcc-src"
builddir="$workdir/gcc-build"
mkdir -p "$srcdir" "$builddir"

# Unpack gcc source (github tarballs nest under <repo>-<rev>/).
tar xf "$src" -C "$srcdir" --strip-components=1

# Unpack mpfr/gmp/mpc into the gcc source tree at fixed names.
# GCC's top-level configure looks for these as in-tree dependencies.
unpack_dep() {
    local tarball="$1" verdir="$2" target="$3"
    local stage; stage="$(mktemp -d "$workdir/.unpack.XXXXXX")"
    tar xf "$tarball" -C "$stage"
    mv "$stage/$verdir" "$srcdir/$target"
    rmdir "$stage"
}
unpack_dep "$mpfrSrc" "$mpfrVer" mpfr
unpack_dep "$gmpSrc"  "$gmpVer"  gmp
unpack_dep "$mpcSrc"  "$mpcVer"  mpc

# Apply the adapted ld-flags patch.
patch -d "$srcdir" -p1 < "$patchFile"

# Substitute the install prefix into gcc/config/sol2.h. After this,
# xgcc (and binaries it later links) will emit -R $out/lib/amd64.
# Note: this does NOT affect the host compiler's own emitted RUNPATHs
# (its specs are already baked into its binary). The LDFLAGS below
# pre-pends $out/lib/amd64 to host-driven links so the resulting
# binaries find their libs in $out first.
sed -i -e "s|@NIX_GCC_PREFIX@|$out|g" "$srcdir/gcc/config/sol2.h"

# Configure in a separate build directory (required by gcc build system).
#
# --disable-bootstrap: skip GCC's 3-stage self-host. If the host
# compiler is already a clean SmartOS-recipe-built compiler (proto.strap
# or a previously-built gcc-illumos), a 3-stage rebuild just re-derives
# what we already have. Saves ~3x build time and avoids stage-N link
# bursts.
#
# LDFLAGS=-Wl,-R$out/lib/amd64: host compiler's specs typically emit
# -R into the host's install dir. This LDFLAGS adds OUR path to the
# same RUNPATH list. Resulting binaries carry both paths; loader checks
# $out/lib/amd64 first (assuming it's listed first). Functional
# correctness only — cosmetic RUNPATH cleanup is deferred.
cd "$builddir"
"$srcdir/configure" \
    --prefix="$out" \
    --disable-bootstrap \
    --build=x86_64-pc-solaris2.11 \
    --host=x86_64-pc-solaris2.11 \
    --target=x86_64-pc-solaris2.11 \
    --with-ld=/usr/bin/ld \
    --without-gnu-ld \
    --with-gnu-as \
    --with-as="$asPath" \
    --enable-languages=c,c++ \
    --enable-shared \
    --disable-nls \
    --disable-multilib \
    CFLAGS="-g -O2 -m64" \
    CXXFLAGS="-g -O2 -m64" \
    LDFLAGS="-Wl,-R$out/lib/amd64"

# Single-stage build (we're --disable-bootstrap'd).
#
# Parallelism: even single-stage, the final cc1plus / cc1 / lto1 /
# lto-dump links happen near-simultaneously and each can hold a
# libbackend.a (smaller on GCC 10 than GCC 14) + several GB of linker
# RSS. The 14-build with --enable-bootstrap wedged a 32 GB host on
# every -j cap (16, 8, 6) when running 3 stages; single-stage at -j6
# cleared comfortably. coresCap=0 (default) means "no cap, use
# NIX_BUILD_CORES"; raise to a positive integer to clamp.
cap="${coresCap:-0}"
cores="${NIX_BUILD_CORES:-1}"
[ "$cores" -eq 0 ] && cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
[ "$cap" -gt 0 ] && [ "$cores" -gt "$cap" ] && cores=$cap
make -j"$cores"
make install
