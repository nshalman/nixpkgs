# gcc-illumos: GCC built per the SmartOS / OmniOS illumos recipe.
#
# Source:  https://github.com/illumos/gcc, tagged gcc-14.2.0-il-1
# Helper libs (mpfr, gmp, mpc) are unpacked into the source tree per the
# SmartOS pattern; GCC's top-level configure picks them up automatically.
# Single patch (1000-ld-flags.patch, adapted from OmniOS) rewrites
# LINK_ARCH64_SPEC_BASE so the resulting xgcc emits $out/lib/amd64 for
# runpath / library search instead of the OmniOS /usr/gcc/<MAJOR>/lib
# convention.
#
# Build approach (since 2026-05-27 pivot): use proto-strap (the
# SmartOS-published GCC-10 strap) as the host compiler and configure
# with --disable-bootstrap (single stage). The pkgsrc/--enable-bootstrap
# combo wedged the host's memory subsystem during the stage-3 link
# burst (4 concurrent xg++ links of cc1/cc1plus/lto1/lto-dump each
# holding ~5-8 GB linker RSS against a ~200 MB libbackend.a). One stage
# = one burst = one OOM-roulette spin instead of three.
#
# Cleanliness contract:
# - Output `xgcc`'s OWN RUNPATH inherits proto-strap's specs and will
#   contain /usr/gcc/10/lib/amd64. The builder additionally passes
#   LDFLAGS=-Wl,-R$out/lib/amd64 so resulting binaries carry BOTH
#   paths in RUNPATH; loader resolves against $out first. Cosmetic
#   removal of the /usr/gcc/10 entry requires string-table extension
#   (elfedit can't widen strings), deferred for a later pass.
# - Output BINARIES THAT xgcc COMPILES use our patched specs and
#   naturally emit $out/lib/amd64 — no cleanup needed downstream.
#
# This is a *standalone* derivation that does not depend on the
# nixpkgs stdenv chain (matching Phase 1 of SMARTOS_RECIPE_ROADMAP.md).
# Phase 2 will build a lean nixpkgs stdenv on top of this compiler.
#
# Usage (smoke test):
#   nix-build -E '(import ./pkgs/development/compilers/gcc-illumos) {}'
#
{
  # SmartOS proto.strap derivation, providing the host GCC + binutils +
  # gas. Default imports the sibling proto-strap package; override to
  # pin a different strap-cache build.
  protoStrap ? import ../proto-strap { },
  # Tools NOT in proto.strap that the GCC build needs at host: make,
  # gawk, patch, flex, bison. illumos /usr/bin covers bash/sed/awk/tar/m4;
  # the rest still come from pkgsrc.
  extraHostPath ? "/opt/local/bin:/usr/bin:/usr/gnu/bin:/usr/sfw/bin",
  system ? "x86_64-illumos",
}:

let
  fetchurl = import <nix/fetchurl.nix>;

  gccVersion = "14.2.0-il-1";
  mpfrVer = "mpfr-4.2.1";
  gmpVer = "gmp-6.3.0";
  mpcVer = "mpc-1.3.1";

  src = fetchurl {
    url = "https://github.com/illumos/gcc/archive/refs/tags/gcc-${gccVersion}.tar.gz";
    sha256 = "18lfswx45lkizs0ygdhhwp5qswb66jqssihwb9wnx6gpw986mgzq";
    name = "gcc-${gccVersion}.tar.gz";
  };

  mpfrSrc = fetchurl {
    url = "https://ftp.gnu.org/gnu/mpfr/${mpfrVer}.tar.bz2";
    sha256 = "183acv9b1ji6kzawzwcxnahlij2a1i11jfv256f0ir10bdir7pxr";
    name = "${mpfrVer}.tar.bz2";
  };

  gmpSrc = fetchurl {
    url = "https://ftp.gnu.org/gnu/gmp/${gmpVer}.tar.bz2";
    sha256 = "1jr03h6h0yz4w9pwyh7p6ijfk3vcsrc6139c5sp9nq7vghd22a5c";
    name = "${gmpVer}.tar.bz2";
  };

  mpcSrc = fetchurl {
    url = "https://ftp.gnu.org/gnu/mpc/${mpcVer}.tar.gz";
    sha256 = "1f2rqz0hdrrhx4y1i5f8pv6yv08a876k1dqcm9s2p26gyn928r5b";
    name = "${mpcVer}.tar.gz";
  };

  # Host PATH: proto.strap's GCC + gas come first, then the pkgsrc /
  # system tools for everything proto.strap doesn't ship.
  hostPath = "${protoStrap}/usr/gcc/10/bin:${protoStrap}/usr/gnu/bin:${extraHostPath}";
  asPath = "${protoStrap}/usr/gnu/bin/gas";

in
derivation {
  name = "gcc-illumos-${gccVersion}";
  inherit system src mpfrSrc gmpSrc mpcSrc hostPath asPath protoStrap;

  inherit mpfrVer gmpVer mpcVer;
  version = gccVersion;

  builder = "/usr/bin/bash";
  args = [ ./builder.sh ];

  patchFile = ./1000-ld-flags.patch;
}
