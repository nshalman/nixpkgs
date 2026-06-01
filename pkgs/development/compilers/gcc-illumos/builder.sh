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
# Outputs:
#   $out/bin/gcc, $out/libexec/.../cc1, $out/include/...
#   $lib/lib/amd64/libgcc_s.so.1, libstdc++.so.6, etc.
# Binaries compiled by gcc-illumos have RUNPATH pointing at $lib only,
# so downstream closures don't pull the full $out compiler.

set -euo pipefail
set -o xtrace

export PATH="$hostPath"

# Pre-create $lib/lib/amd64 as a symlink to $out/lib/amd64. autotools
# installs the runtime libs into $out/lib/amd64 (via --prefix=$out);
# we move them to $lib/lib/amd64 at the end. The symlink keeps any
# spec-driven `-L $lib/lib/amd64` consulted during the build resolving
# to the same location autotools is staging.
mkdir -p "$lib/lib" "$out/lib"
ln -s "$out/lib/amd64" "$lib/lib/amd64"

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
sed -i -e "s|@NIX_GCC_PREFIX@|$lib|g" "$srcdir/gcc/config/sol2.h"

# libgomp/Makefile.in has the Sun-ld versioned-shlib rule:
#   libgomp.ver-sun : libgomp.ver \
#                     $(top_srcdir)/../contrib/make_sunver.pl \
#                     $(libgomp_la_OBJECTS) $(libgomp_la_LIBADD)
# On illumos $(libgomp_la_LIBADD) expands to `-ldl` (libgomp's configure
# sets DL_LIBS=-ldl because dlsym lives in libdl). make then treats -ldl
# as a filename prereq and dies with "no rule to make target '-ldl'".
# Strip $(libgomp_la_LIBADD) from the prereq list; the recipe body still
# references it (the make_sunver.pl invocation reads it for .la→.a path
# rewrites — `-l*` args are silently ignored there).
sed -i \
  -e '/^\(@LIBGOMP_BUILD_VERSIONED_SHLIB[^@]*@\)\+libgomp\.ver-sun *:/,/^[^@\t ]/{ s/\$(libgomp_la_OBJECTS) \$(libgomp_la_LIBADD)/$(libgomp_la_OBJECTS)/; }' \
  "$srcdir/libgomp/Makefile.in"

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
    LDFLAGS="-Wl,-R$lib/lib/amd64"

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

# Move the runtime libs from $out/lib/amd64 to $lib/lib/amd64. The
# pre-build symlink at $lib/lib/amd64 → $out/lib/amd64 gets removed
# first. After the move, binaries we compile (RUNPATH=$lib/lib/amd64)
# find their libs at $lib, and gcc-illumos's own internal binaries
# (cc1plus, lto1, ...) — also built with -R$lib/lib/amd64 — resolve
# to the same place.
rm "$lib/lib/amd64"
mv "$out/lib/amd64" "$lib/lib/amd64"

# Bring $lib's runtime closure clean: remove or move anything that
# would create a $lib → $out reference (cycle).
#  - .la libtool archives: hard-coded $libdir = $out/lib/amd64 strings.
#    Standard nixpkgs practice is to delete them; they're rarely
#    consulted by modern build systems and harm more than they help.
#  - .gdb.py pretty-printer scripts: contain $libdir/$pythondir strings
#    pointing at $out. Not needed at runtime; move to $out so users who
#    want them via $out/share can still find them.
#  - libsanitizer (libasan, libubsan, libtsan, liblsan) + their .spec:
#    libsanitizer's Makefile injects a second `-R $libdir = $out/lib/amd64`
#    into the sanitizer shared libs in addition to our LDFLAGS, so they
#    end up with both paths in DT_RUNPATH. Sanitizers are optional;
#    keep them in $out for now. Promote back to $lib if/when needed.
find "$lib/lib/amd64" -name '*.la' -delete
mkdir -p "$out/lib/amd64"
for f in "$lib"/lib/amd64/*-gdb.py \
         "$lib"/lib/amd64/libasan.* \
         "$lib"/lib/amd64/libubsan.* \
         "$lib"/lib/amd64/libtsan.* \
         "$lib"/lib/amd64/liblsan.* \
         "$lib"/lib/amd64/libsanitizer.spec \
         "$lib"/lib/amd64/libcc1.*; do
    # libcc1 is gcc's plugin-interface shared lib. It was linked by the
    # host (proto.strap) compiler and inherits its RUNPATH + DWARF
    # paths, dragging proto-strap into anything that references $lib.
    # Plugins aren't a runtime concern for compiled programs; keep in
    # $out where gcc-plugins-using tooling can still find it.
    [ -e "$f" ] && mv "$f" "$out/lib/amd64/"
done
