#!/usr/bin/bash
#
# Builder for gcc-illumos: stages the SmartOS-recipe GCC build under
# Nix without depending on the nixpkgs stdenv chain.
#
# Required environment (set by default.nix derivation attrs):
#   $out         install prefix
#   $src         gcc-14.2.0-il-1 source tarball
#   $mpfrSrc     mpfr tarball
#   $gmpSrc      gmp tarball
#   $mpcSrc      mpc tarball
#   $patchFile   adapted 1000-ld-flags.patch
#   $hostPath    colon-separated PATH for the host toolchain
#                (proto.strap's GCC + gas first, then pkgsrc / system
#                 for make/gawk/patch/flex/bison/...)
#   $asPath      absolute path to GNU assembler (gas)
#   $version     "14.2.0-il-1"
#   $mpfrVer     "mpfr-4.2.1"
#   $gmpVer      "gmp-6.3.0"
#   $mpcVer      "mpc-1.3.1"
#
# Output: $out/bin/gcc, $out/lib/amd64/libgcc_s.so.1, etc.

set -euo pipefail
set -o xtrace

export PATH="$hostPath"

# Sanity-check host toolchain. proto.strap supplies gcc/g++ but not
# make/gawk/patch/flex/bison — those still come from the extra host path.
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
# Note: this does NOT affect proto.strap's own emitted RUNPATHs —
# proto.strap's specs are already compiled in. The LDFLAGS below
# pre-pends $out/lib/amd64 to proto.strap's links so the resulting
# binaries find their libs in $out first.
sed -i -e "s|@NIX_GCC_PREFIX@|$out|g" "$srcdir/gcc/config/sol2.h"

# Configure in a separate build directory (required by gcc build system).
#
# --disable-bootstrap: skip GCC's 3-stage self-host. proto.strap is
# already a clean SmartOS-recipe-built compiler; a 3-stage rebuild
# would just re-derive what we already have. Saves ~3x build time and
# avoids the multi-stage link bursts that OOM'd the 32 GB host.
#
# LDFLAGS=-Wl,-R$out/lib/amd64: proto.strap's compiled-in specs emit
# -R /usr/gcc/10/lib/amd64 into every link. This LDFLAGS adds OUR path
# to the same RUNPATH list. Resulting binaries carry both paths; the
# loader checks $out/lib/amd64 first if it's listed first. (Functional
# correctness only — cosmetic RUNPATH cleanup is deferred.)
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
# ~200 MB libbackend.a + ~5-8 GB linker RSS. -j6 limits this enough
# on a 32 GB host. Edit `cap=` below to dial.
cap=6
cores="${NIX_BUILD_CORES:-1}"
if [ "$cores" -eq 0 ] || [ "$cores" -gt "$cap" ]; then
    cores=$cap
fi
make -j"$cores"
make install
