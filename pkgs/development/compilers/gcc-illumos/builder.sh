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
#                (must contain bash, gcc, g++, make, sed, awk, tar, patch)
#   $asPath      absolute path to GNU assembler (gas)
#                — SmartOS uses /usr/gnu/bin/gas; pkgsrc layouts may
#                  instead use /opt/local/bin/gas
#   $version     "14.2.0-il-1"
#   $mpfrVer     "mpfr-4.2.1"
#   $gmpVer      "gmp-6.3.0"
#   $mpcVer      "mpc-1.3.1"
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

# Substitute the install prefix into gcc/config/sol2.h.
sed -i -e "s|@NIX_GCC_PREFIX@|$out|g" "$srcdir/gcc/config/sol2.h"

# Configure in a separate build directory (required by gcc build system).
cd "$builddir"
"$srcdir/configure" \
    --prefix="$out" \
    --enable-bootstrap \
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
    CXXFLAGS="-g -O2 -m64"

# GCC's own 3-stage bootstrap.
#
# Parallelism: GCC's stage-1 compile of gimple-match/generic-match drives
# each cc1plus to ~1 GB RSS. On a 32 GB / 16-core host, -j16 OOM-thrashes
# the box; -j8 leaves ~24 GB headroom for OS + tmpfs and works. To raise
# or lower, edit `cap=` below.
cap=8
cores="${NIX_BUILD_CORES:-1}"
if [ "$cores" -eq 0 ] || [ "$cores" -gt "$cap" ]; then
    cores=$cap
fi
make -j"$cores" bootstrap
make install
